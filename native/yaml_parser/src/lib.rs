use std::borrow::Cow;
use std::collections::hash_map::Entry;
use std::collections::{HashMap, HashSet, VecDeque};
use std::ops::Range;
use std::sync::Mutex;
use std::time::{Duration, Instant};

use num_bigint::{BigInt, Sign};
use rustler::env::{OwnedEnv, SavedTerm};
use rustler::{Atom, Binary, Encoder, Env, ResourceArc, Term};
use saphyr_parser::{
    Event, Marker, Parser, ScalarStyle, ScanError, Span, SpannedEventReceiver, StrInput, Tag,
};

mod atoms {
    rustler::atoms! {
        ok, error, cont, plain,
        yaml11, json, failsafe,
    }
}

const YAML_TAG: &str = "tag:yaml.org,2002:";
const STR: &str = "tag:yaml.org,2002:str";
const INT: &str = "tag:yaml.org,2002:int";
const FLOAT: &str = "tag:yaml.org,2002:float";
const BOOL: &str = "tag:yaml.org,2002:bool";
const NULL: &str = "tag:yaml.org,2002:null";
const BINARY: &str = "tag:yaml.org,2002:binary";
const MAP: &str = "tag:yaml.org,2002:map";
const SEQ: &str = "tag:yaml.org,2002:seq";

// Values aliases may add beyond ten times the values written out, so a small file can't expand into gigabytes
const MAX_ALIASED: usize = 1_000_000;

// Inputs under this size take under a millisecond, so they are parsed in one call
const SLICE_SIZE: usize = 2_000;
// Work done in each call on a larger input, so the scheduler runs other processes in between
const SLICE_TIME: Duration = Duration::from_micros(500);
// Bytes checked for UTF-8 between looks at the clock
const UTF8_CHUNK: usize = 1 << 20;

// Ast builds YAML.AST structs; Plain builds maps and lists, with merge keys resolved
#[derive(Clone, Copy, PartialEq)]
enum Mode {
    Ast,
    Plain { merge: bool },
}

#[derive(Clone, Copy, PartialEq)]
enum Schema {
    Core,
    Yaml11,
    Json,
    Failsafe,
}

type Failure = (String, usize, usize);

fn options(schema: Atom, mode: Term) -> (Schema, Mode) {
    let schema = if schema == atoms::yaml11() {
        Schema::Yaml11
    } else if schema == atoms::json() {
        Schema::Json
    } else if schema == atoms::failsafe() {
        Schema::Failsafe
    } else {
        Schema::Core
    };
    // :ast, or {:plain, enable_merge}
    let mode = match mode.decode::<(Atom, bool)>() {
        Ok((tag, merge)) if tag == atoms::plain() => Mode::Plain { merge },
        _ => Mode::Ast,
    };
    (schema, mode)
}

// Returns {:ok, binary}, {:error, message, line, column}, or {:cont, job} to pass to resume/1
#[rustler::nif]
fn parse<'a>(env: Env<'a>, input: Binary<'a>, schema: Atom, mode: Term<'a>) -> Term<'a> {
    let (schema, mode) = options(schema, mode);
    let bytes = input.as_slice();
    if bytes.len() < SLICE_SIZE {
        // Without a deadline the job always finishes
        let result = Job::new(bytes, schema, mode, 0).step(None).unwrap();
        return reply(env, result);
    }
    // The job keeps its own reference to the input, so the bytes it borrows live as long as it does
    let owned = OwnedEnv::new();
    let saved = owned.save(input);
    let bytes = owned.run(|env| {
        let input: Binary = saved.load(env).decode().unwrap();
        unsafe { std::mem::transmute::<&[u8], &'static [u8]>(input.as_slice()) }
    });
    let job = ResourceArc::new(Resumable {
        job: Mutex::new(Job::new(bytes, schema, mode, 0)),
        _input: Mutex::new((owned, saved)),
    });
    slice(env, job)
}

#[rustler::nif]
fn resume(env: Env<'_>, job: ResourceArc<Resumable>) -> Term<'_> {
    slice(env, job)
}

fn slice(env: Env<'_>, job: ResourceArc<Resumable>) -> Term<'_> {
    let step = job
        .job
        .lock()
        .unwrap()
        .step(Some(Instant::now() + SLICE_TIME));
    rustler::schedule::consume_timeslice(env, 50);
    match step {
        Some(result) => reply(env, result),
        None => (atoms::cont(), job).encode(env),
    }
}

// The result is handed over as a binary in Erlang's external term format, without a copy
fn reply(env: Env<'_>, result: Result<Vec<u8>, Failure>) -> Term<'_> {
    match result {
        Ok(bytes) => {
            let output = ResourceArc::new(Output(bytes));
            (atoms::ok(), output.make_binary(env, |o| &o.0)).encode(env)
        }
        Err((message, line, column)) => (atoms::error(), message, line, column).encode(env),
    }
}

struct Output(Vec<u8>);

#[rustler::resource_impl]
impl rustler::Resource for Output {}

// A job that runs over several calls; it's declared before the input it borrows, so it's dropped first
struct Resumable {
    job: Mutex<Job<'static>>,
    _input: Mutex<(OwnedEnv, SavedTerm)>,
}

#[rustler::resource_impl]
impl rustler::Resource for Resumable {}

// One decode: the UTF-8 check, then the parser's events, a slice at a time
struct Job<'t> {
    bytes: &'t [u8],
    checked: usize,
    schema: Schema,
    mode: Mode,
    // Lines before the input, for a document in a stream
    offset: usize,
    run: Option<(Parser<'t, StrInput<'t>>, Builder<'t>)>,
}

impl<'t> Job<'t> {
    fn new(bytes: &'t [u8], schema: Schema, mode: Mode, offset: usize) -> Self {
        Job {
            bytes,
            checked: 0,
            schema,
            mode,
            offset,
            run: None,
        }
    }

    // None when the deadline passed before the end
    fn step(&mut self, deadline: Option<Instant>) -> Option<Result<Vec<u8>, Failure>> {
        let late = || deadline.is_some_and(|d| Instant::now() >= d);

        while self.checked < self.bytes.len() {
            let end = (self.checked + UTF8_CHUNK).min(self.bytes.len());
            match std::str::from_utf8(&self.bytes[self.checked..end]) {
                Ok(_) => self.checked = end,
                // A character cut by the end of the chunk is checked with the next one
                Err(e) if e.error_len().is_none() && end < self.bytes.len() => {
                    self.checked += e.valid_up_to()
                }
                // Reported at the first byte that isn't UTF-8
                Err(e) => {
                    let before = &self.bytes[..self.checked + e.valid_up_to()];
                    let line = before.iter().filter(|&&b| b == b'\n').count() + 1;
                    let start = before
                        .iter()
                        .rposition(|&b| b == b'\n')
                        .map_or(0, |i| i + 1);
                    let column =
                        std::str::from_utf8(&before[start..]).map_or(1, |s| s.chars().count() + 1);
                    return Some(Err((
                        "invalid UTF-8".to_string(),
                        line + self.offset,
                        column,
                    )));
                }
            }
            if late() {
                return None;
            }
        }

        let (parser, builder) = self.run.get_or_insert_with(|| {
            let text = unsafe { std::str::from_utf8_unchecked(self.bytes) };
            // A byte order mark isn't part of the content
            let text = text.strip_prefix('\u{feff}').unwrap_or(text);
            let builder = Builder::new(self.schema, self.mode, text, self.offset);
            (Parser::new_from_str(text), builder)
        });

        // Events are pulled one by one, since the parser's own loader recurses once per nesting level
        let mut scan_error = None;
        let mut events = 0u32;
        loop {
            match parser.next() {
                Some(Ok((event, span))) => builder.on_event(event, span),
                Some(Err(e)) => scan_error = Some(e),
                None => break,
            }
            if scan_error.is_some() || builder.error.is_some() {
                break;
            }
            events += 1;
            if events.is_multiple_of(64) && late() {
                return None;
            }
        }

        Some(
            match builder
                .error
                .take()
                .or(scan_error.map(|e| end_error(e, builder.text)))
            {
                Some((message, line, column)) => Err((message, line + self.offset, column)),
                None => Ok(builder.finish()),
            },
        )
    }
}

// An error found at the end of the input is reported at the end of the last line
fn end_error(e: ScanError, yaml: &str) -> Failure {
    let (line, col) = (e.marker().line(), e.marker().col() + 1);
    let body = yaml.strip_suffix('\n').unwrap_or(yaml);
    if col == 1 && line == body.matches('\n').count() + 2 {
        let last = body.rsplit('\n').next().unwrap_or("");
        (
            e.info().to_string(),
            line - 1,
            last.trim_end_matches('\r').chars().count() + 1,
        )
    } else {
        (e.info().to_string(), line, col)
    }
}

// Streaming
// ---------

// Decodes chunks as they arrive: each feed returns the documents they completed, in one binary
#[rustler::nif]
fn stream_new(schema: Atom, mode: Term) -> ResourceArc<Streaming> {
    let (schema, mode) = options(schema, mode);
    ResourceArc::new(Streaming(Mutex::new(Stream {
        splitter: Splitter {
            start: 1,
            line: 1,
            ..Splitter::default()
        },
        current: None,
        batch: Vec::new(),
        results: 0,
        ended: false,
        schema,
        mode,
    })))
}

// Each returns {:ok, binary} with a list of {documents, aliased} or {:error, message, line, column},
// :ok when no document was completed, or {:cont, stream} to pass to stream_resume/1
#[rustler::nif]
fn stream_feed<'a>(env: Env<'a>, stream: ResourceArc<Streaming>, chunk: Binary<'a>) -> Term<'a> {
    stream
        .0
        .lock()
        .unwrap()
        .splitter
        .input
        .extend_from_slice(chunk.as_slice());
    stream_slice(env, stream)
}

#[rustler::nif]
fn stream_end(env: Env<'_>, stream: ResourceArc<Streaming>) -> Term<'_> {
    stream.0.lock().unwrap().ended = true;
    stream_slice(env, stream)
}

#[rustler::nif]
fn stream_resume(env: Env<'_>, stream: ResourceArc<Streaming>) -> Term<'_> {
    stream_slice(env, stream)
}

fn stream_slice(env: Env<'_>, stream: ResourceArc<Streaming>) -> Term<'_> {
    let done = stream.0.lock().unwrap().run(Instant::now() + SLICE_TIME);
    rustler::schedule::consume_timeslice(env, 50);
    match done {
        // Most lines of a stream finish no document, so they skip building a binary
        Some(bytes) if bytes == [131, 106] => atoms::ok().encode(env),
        Some(bytes) => reply(env, Ok(bytes)),
        None => (atoms::cont(), stream).encode(env),
    }
}

struct Streaming(Mutex<Stream>);

#[rustler::resource_impl]
impl rustler::Resource for Streaming {}

struct Stream {
    splitter: Splitter,
    current: Option<Document>,
    // The results so far, as list items
    batch: Vec<u8>,
    results: usize,
    ended: bool,
    schema: Schema,
    mode: Mode,
}

// A document being parsed; the job is declared before the text it borrows, so it's dropped first
struct Document {
    job: Job<'static>,
    _text: Box<[u8]>,
}

impl Stream {
    // The batch once every complete document is parsed, or None when the deadline passed
    fn run(&mut self, deadline: Instant) -> Option<Vec<u8>> {
        loop {
            if let Some(document) = &mut self.current {
                match document.job.step(Some(deadline))? {
                    Ok(bytes) => self.batch.extend_from_slice(&bytes[1..]),
                    Err((message, line, column)) => {
                        self.batch.extend_from_slice(&[104, 4]);
                        write_atom(&mut self.batch, "error");
                        write_binary(&mut self.batch, message.as_bytes());
                        write_int(&mut self.batch, line as i64);
                        write_int(&mut self.batch, column as i64);
                    }
                }
                self.results += 1;
                self.current = None;
            }
            if let Some((text, first_line)) = self.splitter.done.pop_front() {
                let text = text.into_boxed_slice();
                // The box's bytes stay put when it moves, and it lives as long as the job
                let bytes = unsafe { std::mem::transmute::<&[u8], &'static [u8]>(&text[..]) };
                self.current = Some(Document {
                    job: Job::new(bytes, self.schema, self.mode, first_line - 1),
                    _text: text,
                });
                continue;
            }
            if !self.splitter.cut(deadline) {
                return None;
            }
            if !self.splitter.done.is_empty() {
                continue;
            }
            if self.ended && !self.splitter.finished {
                self.splitter.finish();
                continue;
            }

            let mut out = vec![131];
            if self.results > 0 {
                out.push(108);
                put_u32(&mut out, self.results);
                out.append(&mut self.batch);
            }
            out.push(106);
            self.results = 0;
            return Some(out);
        }
    }
}

// Cuts streamed text into documents with their first line; a "---" or "..." line ends a document
#[derive(Default)]
struct Splitter {
    // Text not yet cut into lines, from `at`
    input: Vec<u8>,
    at: usize,
    searched: usize,
    // The document's lines so far, each with its line break
    text: Vec<u8>,
    start: usize,
    line: usize,
    in_document: bool,
    finished: bool,
    done: VecDeque<(Vec<u8>, usize)>,
}

impl Splitter {
    // Cuts the complete lines; false when the deadline passed first
    fn cut(&mut self, deadline: Instant) -> bool {
        let mut lines = 0u32;
        // Only new text is searched, so a long line read in many chunks stays linear
        while let Some(i) = self.input[self.searched..].iter().position(|&c| c == b'\n') {
            let end = self.searched + i;
            let line = std::mem::take(&mut self.input);
            self.add_line(&line[self.at..end]);
            self.input = line;
            self.at = end + 1;
            self.searched = self.at;
            lines += 1;
            if lines.is_multiple_of(1024) && Instant::now() >= deadline {
                return false;
            }
        }
        self.searched = self.input.len();
        // Cut text is dropped once it's more than what's left, so moving the rest stays linear
        if self.at > self.input.len() - self.at {
            self.input.drain(..self.at);
            self.searched -= self.at;
            self.at = 0;
        }
        true
    }

    // The last line had no newline, so none is added after it
    fn finish(&mut self) {
        self.finished = true;
        if self.at < self.input.len() {
            let line = std::mem::take(&mut self.input);
            self.add_line(&line[self.at..]);
            self.text.pop();
        }
        (self.at, self.searched) = (0, 0);
        self.finish_document();
    }

    fn add_line(&mut self, line: &[u8]) {
        let marker = |m: &[u8]| {
            line.starts_with(m) && matches!(line.get(3), None | Some(b' ' | b'\t' | b'\r'))
        };
        if marker(b"---") && self.in_document {
            self.finish_document();
            self.start = self.line;
            self.push(line);
        } else if marker(b"...") {
            self.push(line);
            self.finish_document();
            self.start = self.line;
            self.in_document = false;
        } else {
            // Outside a document, a blank line, comment or directive doesn't start one
            let first = line.iter().find(|c| !c.is_ascii_whitespace());
            if first.is_some_and(|c| !matches!(c, b'#' | b'%')) {
                self.in_document = true;
            }
            self.push(line);
        }
    }

    fn push(&mut self, line: &[u8]) {
        self.text.extend_from_slice(line);
        self.text.push(b'\n');
        self.line += 1;
    }

    fn finish_document(&mut self) {
        let text = std::mem::take(&mut self.text);
        if self.in_document {
            self.done.push_back((text, self.start));
        }
    }
}

// Erlang's external term format
// -----------------------------

const MERGE_KEY: [u8; 7] = [109, 0, 0, 0, 2, b'<', b'<'];

// An alias is written as {:__yaml_alias__, index}, and Elixir puts the anchored value in its place
const ALIAS: [u8; 18] = *b"\x68\x02\x77\x0e__yaml_alias__";

fn write_alias(out: &mut Vec<u8>, index: usize) {
    out.extend_from_slice(&ALIAS);
    write_int(out, index as i64);
}

// An alias's anchored value from the table, or the bytes themselves
fn aliased<'b>(bytes: &'b [u8], table: &'b [u8], spans: &[Range<usize>]) -> &'b [u8] {
    alias_index(bytes).map_or(bytes, |i| &table[spans[i].clone()])
}

// The index in an alias's bytes
fn alias_index(b: &[u8]) -> Option<usize> {
    match b.strip_prefix(&ALIAS)? {
        [97, n] => Some(*n as usize),
        [98, n @ ..] => Some(u32::from_be_bytes(n.try_into().ok()?) as usize),
        _ => None,
    }
}

fn put_u32(out: &mut Vec<u8>, n: usize) {
    out.extend_from_slice(&(n as u32).to_be_bytes());
}

fn get_u32(b: &[u8], at: usize) -> usize {
    u32::from_be_bytes([b[at], b[at + 1], b[at + 2], b[at + 3]]) as usize
}

// A list or map header whose length is filled in at the end
fn placeholder(out: &mut Vec<u8>, tag: u8) -> usize {
    out.push(tag);
    out.extend_from_slice(&[0; 4]);
    out.len() - 4
}

fn patch(out: &mut [u8], at: usize, n: usize) {
    out[at..at + 4].copy_from_slice(&(n as u32).to_be_bytes());
}

fn write_atom(out: &mut Vec<u8>, name: &str) {
    out.push(119);
    out.push(name.len() as u8);
    out.extend_from_slice(name.as_bytes());
}

fn write_binary(out: &mut Vec<u8>, bytes: &[u8]) {
    out.push(109);
    put_u32(out, bytes.len());
    out.extend_from_slice(bytes);
}

fn write_int(out: &mut Vec<u8>, i: i64) {
    match i {
        0..=255 => out.extend_from_slice(&[97, i as u8]),
        _ if i32::try_from(i).is_ok() => {
            out.push(98);
            out.extend_from_slice(&(i as i32).to_be_bytes());
        }
        _ => write_big_digits(out, i < 0, &i.unsigned_abs().to_le_bytes()),
    }
}

fn write_big_digits(out: &mut Vec<u8>, negative: bool, digits: &[u8]) {
    let len = digits.iter().rposition(|&d| d != 0).map_or(1, |i| i + 1);
    if len <= 255 {
        out.extend_from_slice(&[110, len as u8]);
    } else {
        out.push(111);
        put_u32(out, len);
    }
    out.push(negative as u8);
    out.extend_from_slice(&digits[..len]);
}

fn write_value(out: &mut Vec<u8>, value: &Value) {
    match value {
        Value::Str(s) => write_binary(out, s.as_bytes()),
        Value::Bytes(b) => write_binary(out, b),
        Value::Int(i) => write_int(out, *i),
        Value::Big(n) => {
            let (sign, digits) = n.to_bytes_le();
            write_big_digits(out, sign == Sign::Minus, &digits)
        }
        Value::Float(f) => {
            out.push(70);
            out.extend_from_slice(&f.to_be_bytes());
        }
        Value::Atom(name) => write_atom(out, name),
    }
}

// A struct is a map with a __struct__ key
fn write_struct(out: &mut Vec<u8>, module: &str, fields: usize) {
    out.push(116);
    put_u32(out, fields + 1);
    write_atom(out, "__struct__");
    write_atom(out, module);
}

// The end of the term at `i`, for the terms written here; a loop, so deep nesting can't overflow the stack
fn skip(b: &[u8], mut i: usize) -> usize {
    let mut pending = 1;
    while pending > 0 {
        pending -= 1;
        i += match b[i] {
            97 => 2,
            98 => 5,
            70 => 9,
            106 => 1,
            110 => 3 + b[i + 1] as usize,
            119 => 2 + b[i + 1] as usize,
            111 => 6 + get_u32(b, i + 1),
            109 => 5 + get_u32(b, i + 1),
            108 => {
                pending += get_u32(b, i + 1) + 1;
                5
            }
            116 => {
                pending += 2 * get_u32(b, i + 1);
                5
            }
            104 => {
                pending += b[i + 1] as usize;
                2
            }
            _ => unreachable!("a term this builder doesn't write"),
        };
    }
    i
}

// The key and value ranges of the map at `i`
fn map_pairs(b: &[u8], i: usize) -> Vec<(Range<usize>, Range<usize>)> {
    let mut at = i + 5;
    (0..get_u32(b, i + 1))
        .map(|_| {
            let key = at..skip(b, at);
            let value = key.end..skip(b, key.end);
            at = value.end;
            (key, value)
        })
        .collect()
}

// The item ranges of the list at `i`
fn list_items(b: &[u8], i: usize) -> Vec<Range<usize>> {
    let mut at = i + 5;
    (0..get_u32(b, i + 1))
        .map(|_| {
            let item = at..skip(b, at);
            at = item.end;
            item
        })
        .collect()
}

// Builder
// -------

// A collection being written; its position is fixed when its first child arrives, since its start event can come late
struct Frame {
    map: bool,
    start: usize,
    count_at: usize,
    count: usize,
    // A map's key, waiting for its value
    key: Option<Range<usize>>,
    // A plain map's pairs, to resolve merge keys and duplicate keys at its end
    pairs: Vec<(Range<usize>, Range<usize>)>,
    size: usize,
    tag: Cow<'static, str>,
    mark: Marker,
    anchor: usize,
}

// Writes the documents from parser events as Erlang terms
struct Builder<'t> {
    text: &'t str,
    source: Source<'t>,
    last_end: Marker,
    schema: Schema,
    mode: Mode,
    stack: Vec<Frame>,
    out: Vec<u8>,
    documents: usize,
    offset: usize,
    // Each anchored node's bytes, its number of values, and its index in the table once aliased
    anchors: HashMap<usize, (Vec<u8>, usize, Option<usize>)>,
    // The values of aliased anchors, written once each
    table: Vec<u8>,
    spans: Vec<Range<usize>>,
    aliased: usize,
    written: usize,
    error: Option<Failure>,
}

impl<'t> Builder<'t> {
    fn new(schema: Schema, mode: Mode, text: &'t str, offset: usize) -> Self {
        // {documents, aliased values}
        let mut out = vec![131, 104, 2];
        placeholder(&mut out, 108);
        Builder {
            text,
            source: Source::new(text),
            last_end: Marker::new(0, 1, 0),
            schema,
            mode,
            stack: Vec::new(),
            out,
            documents: 0,
            offset,
            anchors: HashMap::new(),
            table: Vec::new(),
            spans: Vec::new(),
            aliased: 0,
            written: 0,
            error: None,
        }
    }

    fn finish(&mut self) -> Vec<u8> {
        patch(&mut self.out, 4, self.documents);
        self.out.push(106);
        if !self.spans.is_empty() {
            self.out.push(108);
            put_u32(&mut self.out, self.spans.len());
            self.out.extend_from_slice(&self.table);
        }
        self.out.push(106);
        std::mem::take(&mut self.out)
    }

    fn ast(&self) -> bool {
        self.mode == Mode::Ast
    }

    // Writes what goes before a node: a document around a root, or a tuple around a key and its value
    fn begin(&mut self) -> usize {
        if self.ast() {
            match self.stack.last() {
                None => {
                    write_struct(&mut self.out, "Elixir.YAML.AST.Document", 1);
                    write_atom(&mut self.out, "root");
                }
                Some(Frame {
                    map: true,
                    key: None,
                    ..
                }) => self.out.extend_from_slice(&[104, 2]),
                _ => {}
            }
        }
        self.out.len()
    }

    fn meta(&mut self, tag: &str, mark: Marker) {
        write_atom(&mut self.out, "meta");
        write_struct(&mut self.out, "Elixir.YAML.AST.Meta", 3);
        write_atom(&mut self.out, "tag");
        write_binary(&mut self.out, tag.as_bytes());
        write_atom(&mut self.out, "line");
        write_int(&mut self.out, (mark.line() + self.offset) as i64);
        write_atom(&mut self.out, "column");
        write_int(&mut self.out, mark.col() as i64 + 1);
    }

    fn collection_tag(&self, tag: Option<&Tag>, default: &'static str) -> Cow<'static, str> {
        match tag {
            Some(t) if !is_non_specific(t) => full_tag(t).into(),
            _ => default.into(),
        }
    }

    fn fail(&mut self, message: String, mark: Marker) {
        if self.error.is_none() {
            self.error = Some((message, mark.line(), mark.col() + 1));
        }
    }

    fn add(&mut self, start: usize, node_size: usize, anchor: usize, mark: Marker) {
        let end = self.out.len();
        if anchor != 0 {
            self.anchors
                .insert(anchor, (self.out[start..end].to_vec(), node_size, None));
        }

        // A sequence starts at the "-" or "[" before its first item; a mapping at its first key,
        // or the "{" or "?" before it
        if self.ast() {
            let found = match self.stack.last() {
                Some(f) if !f.map && f.count == 0 => self.source.before(mark, b"-["),
                Some(f) if f.map && f.count == 0 && f.key.is_none() => {
                    Some(self.source.before(mark, b"{?").unwrap_or(mark))
                }
                _ => None,
            };
            if let (Some(found), Some(f)) = (found, self.stack.last_mut()) {
                f.mark = found;
            }
        }

        let plain = !self.ast();
        match self.stack.last_mut() {
            None => self.documents += 1,
            Some(f) if !f.map => {
                f.count += 1;
                f.size += node_size;
            }
            Some(f) => {
                f.size += node_size;
                match f.key.take() {
                    None => f.key = Some(start..end),
                    Some(key) => {
                        f.count += 1;
                        if plain {
                            f.pairs.push((key, start..end));
                        }
                    }
                }
            }
        }
    }

    // Merged pairs come first, so the mapping's own keys win, and earlier merged maps win over later ones
    fn plain_map(&mut self, frame: Frame, merge: bool) {
        let (out, table, spans) = (&self.out, &self.table, &self.spans);
        let resolve = |bytes| aliased(bytes, table, spans);
        let is_merge = |key: &Range<usize>| merge && out[key.clone()] == MERGE_KEY;
        let merges = frame.pairs.iter().any(|(key, _)| is_merge(key));
        let mut keys = HashSet::with_capacity(frame.pairs.len());
        if !merges
            && frame
                .pairs
                .iter()
                .all(|(key, _)| keys.insert(resolve(&out[key.clone()])))
        {
            patch(&mut self.out, frame.count_at, frame.count);
            return;
        }

        let mut entries: Vec<(&[u8], &[u8])> = Vec::new();
        for (_, value) in frame.pairs.iter().filter(|(key, _)| is_merge(key)) {
            let value = resolve(&out[value.clone()]);
            let maps = match value[0] {
                108 => list_items(value, 0)
                    .into_iter()
                    .map(|item| resolve(&value[item]))
                    .collect(),
                _ => vec![value],
            };
            for map in maps.into_iter().rev().filter(|map| map[0] == 116) {
                entries.extend(
                    map_pairs(map, 0)
                        .into_iter()
                        .map(|(k, v)| (&map[k], &map[v])),
                );
            }
        }
        entries.extend(
            frame
                .pairs
                .iter()
                .filter(|(key, _)| !is_merge(key))
                .map(|(k, v)| (&out[k.clone()], &out[v.clone()])),
        );

        // Duplicate keys keep the last value, with an alias the same key as its anchor
        let mut index: HashMap<&[u8], usize> = HashMap::new();
        let mut unique: Vec<(&[u8], &[u8])> = Vec::new();
        for (key, value) in entries {
            match index.entry(resolve(key)) {
                Entry::Occupied(e) => unique[*e.get()].1 = value,
                Entry::Vacant(e) => {
                    e.insert(unique.len());
                    unique.push((key, value));
                }
            }
        }

        let mut map = Vec::with_capacity(out.len() - frame.start);
        map.push(116);
        put_u32(&mut map, unique.len());
        for (key, value) in unique {
            map.extend_from_slice(key);
            map.extend_from_slice(value);
        }
        self.out.truncate(frame.start);
        self.out.extend_from_slice(&map);
    }

    fn scalar(
        &mut self,
        text: &str,
        style: ScalarStyle,
        anchor: usize,
        tag: Option<&Tag>,
        mark: Marker,
    ) {
        match resolve(self.schema, text, style, tag) {
            Ok((tag, value)) => {
                let start = self.begin();
                if self.ast() {
                    write_struct(&mut self.out, "Elixir.YAML.AST.Scalar", 2);
                    write_atom(&mut self.out, "value");
                    write_value(&mut self.out, &value);
                    self.meta(&tag, mark);
                } else {
                    write_value(&mut self.out, &value);
                }
                self.written += 1;
                self.add(start, 1, anchor, mark);
            }
            Err(message) => self.fail(message, mark),
        }
    }

    fn open(&mut self, map: bool, tag: Cow<'static, str>, mark: Marker, anchor: usize) {
        let start = self.begin();
        let count_at = match (self.ast(), map) {
            (true, false) => {
                write_struct(&mut self.out, "Elixir.YAML.AST.List", 3);
                write_atom(&mut self.out, "items");
                placeholder(&mut self.out, 108)
            }
            (true, true) => {
                write_struct(&mut self.out, "Elixir.YAML.AST.Mapping", 2);
                write_atom(&mut self.out, "pairs");
                placeholder(&mut self.out, 108)
            }
            (false, false) => placeholder(&mut self.out, 108),
            (false, true) => placeholder(&mut self.out, 116),
        };
        self.stack.push(Frame {
            map,
            start,
            count_at,
            count: 0,
            key: None,
            pairs: Vec::new(),
            size: 1,
            tag,
            mark,
            anchor,
        });
    }

    fn close(&mut self) {
        let Some(frame) = self.stack.pop() else {
            return;
        };
        let (start, size, anchor, mark) = (frame.start, frame.size, frame.anchor, frame.mark);
        match self.mode {
            Mode::Plain { merge } if frame.map => self.plain_map(frame, merge),
            _ => {
                patch(&mut self.out, frame.count_at, frame.count);
                self.out.push(106);
                if self.ast() {
                    self.meta(&frame.tag, mark);
                    if !frame.map {
                        write_atom(&mut self.out, "length");
                        write_int(&mut self.out, frame.count as i64);
                    }
                }
            }
        }
        self.written += 1;
        self.add(start, size, anchor, mark);
    }
}

impl<'input> SpannedEventReceiver<'input> for Builder<'_> {
    fn on_event(&mut self, event: Event<'input>, span: Span) {
        if self.error.is_some() {
            return;
        }

        let mark = span.start;
        let from = std::mem::replace(&mut self.last_end, span.end);
        match event {
            Event::Scalar(text, style, anchor, tag) => {
                // A block scalar starts at its "|" or ">", not at its first line of text
                // An empty value sits right after the token before it
                let mark = match style {
                    ScalarStyle::Literal | ScalarStyle::Folded => {
                        self.source.find(from, mark, b"|>").unwrap_or(mark)
                    }
                    ScalarStyle::Plain if text.is_empty() && tag.is_none() => from,
                    _ => mark,
                };
                self.scalar(&text, style, anchor, tag.as_deref(), mark)
            }
            Event::SequenceStart(anchor, tag) => {
                let tag = self.collection_tag(tag.as_deref(), SEQ);
                self.open(false, tag, mark, anchor);
            }
            Event::MappingStart(anchor, tag) => {
                let tag = self.collection_tag(tag.as_deref(), MAP);
                self.open(true, tag, mark, anchor);
            }
            Event::SequenceEnd | Event::MappingEnd => self.close(),
            // An anchor only belongs to its own document
            Event::DocumentStart(_) => self.anchors.clear(),
            Event::Alias(id) => match self.anchors.get_mut(&id) {
                Some((bytes, size, index)) => {
                    let size = *size;
                    // The anchored value goes in the table the first time it's aliased
                    let index = *index.get_or_insert_with(|| {
                        let at = self.table.len();
                        self.table.extend_from_slice(bytes);
                        self.spans.push(at..self.table.len());
                        self.spans.len() - 1
                    });
                    self.aliased += size;
                    if self.aliased > MAX_ALIASED.max(10 * self.written) {
                        self.fail("aliases expand to too many values".to_string(), mark);
                    } else {
                        let start = self.begin();
                        write_alias(&mut self.out, index);
                        self.add(start, size, 0, mark);
                    }
                }
                None => self.fail("unknown anchor".to_string(), mark),
            },
            _ => {}
        }
    }
}

// Source positions
// ----------------

// Finds characters by line and column, moving forward through the text, so lookups stay linear
struct Source<'a> {
    text: &'a [u8],
    line_starts: Vec<usize>,
    cursor: (usize, usize, usize),
}

impl<'a> Source<'a> {
    fn new(text: &'a str) -> Self {
        Source {
            text: text.as_bytes(),
            line_starts: vec![0],
            cursor: (1, 0, 0),
        }
    }

    // Start of a 1-indexed line; line breaks are found only as far as needed, so a large input isn't scanned at once
    fn line_start(&mut self, line: usize) -> Option<usize> {
        while self.line_starts.len() < line {
            let from = *self.line_starts.last()?;
            let at = self.text[from..].iter().position(|&c| c == b'\n')?;
            self.line_starts.push(from + at + 1);
        }
        self.line_starts.get(line.checked_sub(1)?).copied()
    }

    // Byte offset of a 1-indexed line and 0-indexed character column
    fn offset(&mut self, line: usize, col: usize) -> Option<usize> {
        let (cur_line, cur_col, cur_byte) = self.cursor;
        let (mut c, mut byte) = if line == cur_line && col >= cur_col {
            (cur_col, cur_byte)
        } else {
            (0, self.line_start(line)?)
        };
        while c < col {
            let b = *self.text.get(byte)?;
            byte += if b < 0x80 {
                1
            } else if b >= 0xF0 {
                4
            } else if b >= 0xE0 {
                3
            } else {
                2
            };
            c += 1;
        }
        self.cursor = (line, col, byte);
        Some(byte)
    }

    // One of `targets` just before a position, with only blanks and line breaks between
    fn before(&mut self, at: Marker, targets: &[u8]) -> Option<Marker> {
        let mut i = self.offset(at.line(), at.col())?;
        let mut line = at.line();
        while i > 0 {
            i -= 1;
            match self.text[i] {
                b' ' | b'\t' | b'\r' => {}
                b'\n' => line -= 1,
                c if targets.contains(&c) => {
                    let start = self.line_starts[line - 1];
                    let col = std::str::from_utf8(&self.text[start..i])
                        .map_or(i - start, |s| s.chars().count());
                    return Some(Marker::new(0, line, col));
                }
                _ => return None,
            }
        }
        None
    }

    // The first of `targets` between two positions, skipping comments and verbatim tags
    fn find(&mut self, from: Marker, to: Marker, targets: &[u8]) -> Option<Marker> {
        let start = self.offset(from.line(), from.col())?;
        let end = self.offset(to.line(), to.col())?;
        let (mut i, mut line, mut col) = (start, from.line(), from.col());
        while i < end {
            match self.text[i] {
                b'#' => {
                    while i < end && self.text[i] != b'\n' {
                        i += 1;
                    }
                    continue;
                }
                b'\n' => {
                    i += 1;
                    line += 1;
                    col = 0;
                    continue;
                }
                b'!' if self.text.get(i + 1) == Some(&b'<') => {
                    while i < end && self.text[i] != b'>' {
                        i += 1;
                        col += 1;
                    }
                }
                c if targets.contains(&c) => return Some(Marker::new(0, line, col)),
                _ => {}
            }
            let b = self.text[i];
            i += if b < 0x80 {
                1
            } else if b >= 0xF0 {
                4
            } else if b >= 0xE0 {
                3
            } else {
                2
            };
            col += 1;
        }
        None
    }
}

fn full_tag(tag: &Tag) -> String {
    format!("{}{}", tag.handle, tag.suffix)
}

// A lone "!" asks for the default type of the node's kind
fn is_non_specific(tag: &Tag) -> bool {
    tag.handle.is_empty() && tag.suffix == "!"
}

// Scalars
// -------

// A scalar's value, as written to the result
enum Value<'t> {
    Str(&'t str),
    Bytes(Vec<u8>),
    Int(i64),
    Big(BigInt),
    Float(f64),
    Atom(&'static str),
}

const NIL: Value = Value::Atom("nil");

fn boolean(b: bool) -> Value<'static> {
    Value::Atom(if b { "true" } else { "false" })
}

// A value with its tag
type Typed<'t> = (Cow<'static, str>, Value<'t>);

fn resolve<'t>(
    schema: Schema,
    text: &'t str,
    style: ScalarStyle,
    tag: Option<&Tag>,
) -> Result<Typed<'t>, String> {
    let str = || (STR.into(), Value::Str(text));

    match tag {
        Some(t) if is_non_specific(t) => Ok(str()),
        Some(t) if t.handle == YAML_TAG => match t.suffix.as_str() {
            "str" => Ok(str()),
            "int" => core_number(text)
                .or_else(|| yaml11_number(text))
                .filter(|(tag, _)| tag == INT)
                .ok_or("invalid integer".to_string()),
            "float" => float(text)
                .map(|v| (FLOAT.into(), v))
                .ok_or("invalid float".to_string()),
            "bool" => bool_11(text)
                .map(|b| (BOOL.into(), boolean(b)))
                .ok_or("invalid boolean".to_string()),
            "null" => Ok((NULL.into(), NIL)),
            "binary" => base64(text)
                .map(|b| (BINARY.into(), Value::Bytes(b)))
                .ok_or("invalid binary".to_string()),
            _ => Ok((full_tag(t).into(), Value::Str(text))),
        },
        Some(t) => Ok((full_tag(t).into(), Value::Str(text))),
        None if style != ScalarStyle::Plain => Ok(str()),
        None => plain(schema, text),
    }
}

fn plain(schema: Schema, text: &str) -> Result<Typed<'_>, String> {
    let str = || (STR.into(), Value::Str(text));
    let null = || (NULL.into(), NIL);

    match schema {
        Schema::Failsafe => Ok(str()),
        Schema::Json => match text {
            "null" | "" => Ok(null()),
            "true" => Ok((BOOL.into(), boolean(true))),
            "false" => Ok((BOOL.into(), boolean(false))),
            _ if json_int(text) => Ok((INT.into(), int(text).unwrap())),
            _ if json_float(text) => float(text)
                .map(|v| (FLOAT.into(), v))
                .ok_or("invalid float".to_string()),
            _ => Err("invalid plain scalar for the JSON schema".to_string()),
        },
        Schema::Core => match text {
            "" | "~" | "null" | "Null" | "NULL" => Ok(null()),
            "true" | "True" | "TRUE" => Ok((BOOL.into(), boolean(true))),
            "false" | "False" | "FALSE" => Ok((BOOL.into(), boolean(false))),
            _ => Ok(core_number(text).unwrap_or_else(str)),
        },
        Schema::Yaml11 => match text {
            "" | "~" | "null" | "Null" | "NULL" => Ok(null()),
            _ => match bool_11(text) {
                Some(b) => Ok((BOOL.into(), boolean(b))),
                None => Ok(yaml11_number(text).unwrap_or_else(str)),
            },
        },
    }
}

fn special_float(text: &str) -> Option<Value<'static>> {
    match text {
        ".inf" | ".Inf" | ".INF" | "+.inf" | "+.Inf" | "+.INF" => Some(Value::Atom("+inf")),
        "-.inf" | "-.Inf" | "-.INF" => Some(Value::Atom("-inf")),
        ".nan" | ".NaN" | ".NAN" => Some(Value::Atom("nan")),
        _ => None,
    }
}

// Core: [-+]?[0-9]+, 0o[0-7]+, 0x[0-9a-fA-F]+, and floats with an optional exponent
fn core_number(text: &str) -> Option<Typed<'static>> {
    if let Some(v) = special_float(text) {
        return Some((FLOAT.into(), v));
    }
    if let Some(digits) = text.strip_prefix("0o") {
        return radix(digits, 8, false).map(|v| (INT.into(), v));
    }
    if let Some(digits) = text.strip_prefix("0x") {
        return radix(digits, 16, false).map(|v| (INT.into(), v));
    }
    let (_, body) = sign(text);
    if !body.is_empty() && body.bytes().all(|c| c.is_ascii_digit()) {
        return int(text).map(|v| (INT.into(), v));
    }
    if core_float(body) {
        return float(text).map(|v| (FLOAT.into(), v));
    }
    None
}

// YAML 1.1: binary, octal, hex, underscores and base 60, plus floats with underscores
fn yaml11_number(text: &str) -> Option<Typed<'static>> {
    if let Some(v) = special_float(text) {
        return Some((FLOAT.into(), v));
    }
    let (negative, body) = sign(text);
    if let Some(digits) = body.strip_prefix("0b") {
        return radix(digits, 2, negative).map(|v| (INT.into(), v));
    }
    if let Some(digits) = body.strip_prefix("0x") {
        return radix(digits, 16, negative).map(|v| (INT.into(), v));
    }
    if body.len() > 1
        && body.starts_with('0')
        && body.bytes().all(|c| matches!(c, b'0'..=b'7' | b'_'))
    {
        return radix(&body[1..], 8, negative).map(|v| (INT.into(), v));
    }
    if body.contains(':') {
        return sexagesimal(body, negative);
    }
    let digits: String = body.chars().filter(|&c| c != '_').collect();
    let first = body.as_bytes().first().copied();
    if !digits.is_empty() && first != Some(b'_') && digits.bytes().all(|c| c.is_ascii_digit()) {
        let signed = if negative {
            format!("-{digits}")
        } else {
            digits
        };
        return int(&signed).map(|v| (INT.into(), v));
    }
    // A YAML 1.1 float needs a dot, and a sign on its exponent
    let signed_exponent = match digits.find(['e', 'E']) {
        Some(i) => matches!(digits.as_bytes().get(i + 1), Some(b'+' | b'-')),
        None => true,
    };
    if first != Some(b'_') && core_float(&digits) && digits.contains('.') && signed_exponent {
        let signed = if negative {
            format!("-{digits}")
        } else {
            digits
        };
        return float(&signed).map(|v| (FLOAT.into(), v));
    }
    None
}

// 190:20:30 is 190 * 3600 + 20 * 60 + 30; a fraction on the last part makes it a float
fn sexagesimal(body: &str, negative: bool) -> Option<Typed<'static>> {
    let parts: Vec<&str> = body.split(':').collect();
    let (last, rest) = parts.split_last()?;
    if rest.is_empty() || rest[0].is_empty() || rest[0].starts_with('0') {
        return None;
    }
    let mut total = 0f64;
    let mut whole: i64 = 0;
    for (i, part) in rest.iter().enumerate() {
        let part: String = part.chars().filter(|&c| c != '_').collect();
        if part.is_empty() || !part.bytes().all(|c| c.is_ascii_digit()) {
            return None;
        }
        let n: i64 = part.parse().ok()?;
        if i > 0 && n > 59 {
            return None;
        }
        whole = whole.checked_mul(60)?.checked_add(n)?;
    }
    let last: String = last.chars().filter(|&c| c != '_').collect();
    let sign = if negative { -1 } else { 1 };
    if last.bytes().all(|c| c.is_ascii_digit()) && !last.is_empty() && last.len() <= 2 {
        let n: i64 = last.parse().ok()?;
        if n > 59 {
            return None;
        }
        return Some((INT.into(), Value::Int(sign * (whole * 60 + n))));
    }
    let n: f64 = last.parse().ok()?;
    if !(0.0..60.0).contains(&n) || !last.contains('.') {
        return None;
    }
    total += whole as f64 * 60.0 + n;
    Some((FLOAT.into(), Value::Float(sign as f64 * total)))
}

fn sign(text: &str) -> (bool, &str) {
    match text.as_bytes().first() {
        Some(b'-') => (true, &text[1..]),
        Some(b'+') => (false, &text[1..]),
        _ => (false, text),
    }
}

fn core_float(body: &str) -> bool {
    let b = body.as_bytes();
    let mut i = 0;
    let int_digits = count(b, &mut i, |c| c.is_ascii_digit());
    let mut frac_digits = 0;
    if i < b.len() && b[i] == b'.' {
        i += 1;
        frac_digits = count(b, &mut i, |c| c.is_ascii_digit());
    } else if i < b.len() && !matches!(b[i], b'e' | b'E') {
        return false;
    }
    if int_digits + frac_digits == 0 {
        return false;
    }
    if i < b.len() && matches!(b[i], b'e' | b'E') {
        i += 1;
        if i < b.len() && matches!(b[i], b'-' | b'+') {
            i += 1;
        }
        if count(b, &mut i, |c| c.is_ascii_digit()) == 0 {
            return false;
        }
    }
    i == b.len()
}

fn json_int(text: &str) -> bool {
    let body = text.strip_prefix('-').unwrap_or(text);
    body == "0"
        || (!body.is_empty() && !body.starts_with('0') && body.bytes().all(|c| c.is_ascii_digit()))
}

fn json_float(text: &str) -> bool {
    let body = text.strip_prefix('-').unwrap_or(text);
    let int_part = body.split(['.', 'e', 'E']).next().unwrap_or("");
    (int_part == "0" || json_int(int_part)) && core_float(body) && !body.starts_with('.')
}

fn count(b: &[u8], i: &mut usize, f: impl Fn(u8) -> bool) -> usize {
    let start = *i;
    while *i < b.len() && f(b[*i]) {
        *i += 1;
    }
    *i - start
}

fn bool_11(text: &str) -> Option<bool> {
    match text {
        "y" | "Y" | "yes" | "Yes" | "YES" | "true" | "True" | "TRUE" | "on" | "On" | "ON" => {
            Some(true)
        }
        "n" | "N" | "no" | "No" | "NO" | "false" | "False" | "FALSE" | "off" | "Off" | "OFF" => {
            Some(false)
        }
        _ => None,
    }
}

// Integers of any size, as small integers when they fit
fn int(text: &str) -> Option<Value<'static>> {
    let text = text.strip_prefix('+').unwrap_or(text);
    match text.parse::<i64>() {
        Ok(i) => Some(Value::Int(i)),
        Err(_) => BigInt::parse_bytes(text.as_bytes(), 10).map(Value::Big),
    }
}

fn radix(digits: &str, base: u32, negative: bool) -> Option<Value<'static>> {
    let digits: String = digits.chars().filter(|&c| c != '_').collect();
    let n = BigInt::parse_bytes(digits.as_bytes(), base)?;
    let n = if negative { -n } else { n };
    Some(match i64::try_from(&n) {
        Ok(i) => Value::Int(i),
        Err(_) => Value::Big(n),
    })
}

fn float(text: &str) -> Option<Value<'static>> {
    if let Some(v) = special_float(text) {
        return Some(v);
    }
    let cleaned: String = text.chars().filter(|&c| c != '_').collect();
    let (_, body) = sign(&cleaned);
    if !core_float(body) {
        return None;
    }
    cleaned
        .parse::<f64>()
        .ok()
        .filter(|f| f.is_finite())
        .map(Value::Float)
}

// Base64 with whitespace allowed between characters
fn base64(text: &str) -> Option<Vec<u8>> {
    let mut out = Vec::with_capacity(text.len() * 3 / 4);
    let (mut acc, mut bits, mut padding, mut chars) = (0u32, 0, 0, 0);
    for c in text.bytes() {
        let v = match c {
            b'A'..=b'Z' => c - b'A',
            b'a'..=b'z' => c - b'a' + 26,
            b'0'..=b'9' => c - b'0' + 52,
            b'+' => 62,
            b'/' => 63,
            b'=' => {
                padding += 1;
                chars += 1;
                continue;
            }
            b' ' | b'\n' | b'\r' | b'\t' => continue,
            _ => return None,
        };
        if padding > 0 {
            return None;
        }
        chars += 1;
        acc = (acc << 6) | v as u32;
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            out.push((acc >> bits) as u8);
        }
    }
    if chars % 4 != 0 || padding > 2 {
        return None;
    }
    Some(out)
}

rustler::init!("Elixir.YAML.Native");
