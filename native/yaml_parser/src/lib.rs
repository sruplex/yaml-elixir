use std::collections::HashMap;

use num_bigint::BigInt;
use rustler::{Atom, Binary, Encoder, Env, NifResult, Term};
use saphyr_parser::{Event, Marker, Parser, ScalarStyle, Span, SpannedEventReceiver, Tag};

mod atoms {
    rustler::atoms! {
        ok, error, nil,
        core, yaml11, json, failsafe,
        nan, inf = "+inf", neg_inf = "-inf",
        __struct__, value, meta, tag, line, column, items, length, pairs, root,
        document = "Elixir.YAML.AST.Document",
        scalar = "Elixir.YAML.AST.Scalar",
        list = "Elixir.YAML.AST.List",
        mapping = "Elixir.YAML.AST.Mapping",
        meta_struct = "Elixir.YAML.AST.Meta",
    }
}

const YAML_TAG: &str = "tag:yaml.org,2002:";

// Values aliases may add beyond ten times the values written out, so a small file can't expand into gigabytes
const MAX_ALIASED: usize = 1_000_000;

#[derive(Clone, Copy, PartialEq)]
enum Schema {
    Core,
    Yaml11,
    Json,
    Failsafe,
}

// Small inputs take under a millisecond, so they run on a normal scheduler
#[rustler::nif]
fn parse<'a>(env: Env<'a>, input: Binary<'a>, schema: Atom) -> NifResult<Term<'a>> {
    parse_input(env, input, schema)
}

#[rustler::nif(schedule = "DirtyCpu")]
fn parse_dirty<'a>(env: Env<'a>, input: Binary<'a>, schema: Atom) -> NifResult<Term<'a>> {
    parse_input(env, input, schema)
}

fn parse_input<'a>(env: Env<'a>, input: Binary<'a>, schema: Atom) -> NifResult<Term<'a>> {
    let bytes = input.as_slice();
    let yaml = match std::str::from_utf8(bytes) {
        Ok(text) => text,
        // Reported at the first byte that isn't UTF-8
        Err(e) => {
            let before = &bytes[..e.valid_up_to()];
            let line = before.iter().filter(|&&b| b == b'\n').count() + 1;
            let start = before
                .iter()
                .rposition(|&b| b == b'\n')
                .map_or(0, |i| i + 1);
            let column = std::str::from_utf8(&before[start..]).map_or(1, |s| s.chars().count() + 1);
            return Ok((atoms::error(), "invalid UTF-8", line, column).encode(env));
        }
    };

    let schema = if schema == atoms::yaml11() {
        Schema::Yaml11
    } else if schema == atoms::json() {
        Schema::Json
    } else if schema == atoms::failsafe() {
        Schema::Failsafe
    } else {
        Schema::Core
    };

    // A byte order mark isn't part of the content
    let yaml = yaml.strip_prefix('\u{feff}').unwrap_or(yaml);
    // Events are pulled one by one, since the parser's own loader recurses once per nesting level
    let mut builder = Builder::new(env, schema, yaml);
    let mut scan_error = None;
    for item in Parser::new_from_str(yaml) {
        match item {
            Ok((event, span)) => builder.on_event(event, span),
            Err(e) => scan_error = Some(end_of_text(yaml, e.info(), e.marker())),
        }
        if scan_error.is_some() || builder.error.is_some() {
            break;
        }
    }

    let error = builder.error.take().or(scan_error);

    Ok(match error {
        Some((message, line, column)) => (atoms::error(), message, line, column).encode(env),
        None => (atoms::ok(), builder.documents).encode(env),
    })
}

// An error found at the end of the input is reported at the end of the last line
fn end_of_text(yaml: &str, info: &str, mark: &Marker) -> (String, usize, usize) {
    let (line, col) = (mark.line(), mark.col() + 1);
    let body = yaml.strip_suffix('\n').unwrap_or(yaml);

    if col == 1 && line == body.matches('\n').count() + 2 {
        let last = body.rsplit('\n').next().unwrap_or("");
        let col = last.trim_end_matches('\r').chars().count() + 1;
        (info.to_string(), line - 1, col)
    } else {
        (info.to_string(), line, col)
    }
}

// A collection's start event can come late, so its position is fixed when its first child arrives
enum Frame<'a> {
    Seq {
        items: Vec<Term<'a>>,
        size: usize,
        tag: Term<'a>,
        mark: Marker,
        anchor: usize,
    },
    Map {
        pairs: Vec<Term<'a>>,
        key: Option<Term<'a>>,
        size: usize,
        tag: Term<'a>,
        mark: Marker,
        anchor: usize,
    },
}

// Builds YAML.AST structs from parser events
struct Builder<'a> {
    env: Env<'a>,
    source: Source<'a>,
    last_end: Marker,
    schema: Schema,
    stack: Vec<Frame<'a>>,
    documents: Vec<Term<'a>>,
    // Each anchored node with its number of values
    anchors: HashMap<usize, (Term<'a>, usize)>,
    aliased: usize,
    written: usize,
    tags: Tags<'a>,
    error: Option<(String, usize, usize)>,
}

// Tag binaries made once per call, since most nodes share them
struct Tags<'a> {
    str: Term<'a>,
    int: Term<'a>,
    float: Term<'a>,
    bool: Term<'a>,
    null: Term<'a>,
    binary: Term<'a>,
    map: Term<'a>,
    seq: Term<'a>,
}

impl<'a> Builder<'a> {
    fn new(env: Env<'a>, schema: Schema, yaml: &'a str) -> Self {
        let t = |name: &str| format!("{YAML_TAG}{name}").encode(env);

        Builder {
            env,
            source: Source::new(yaml),
            last_end: Marker::new(0, 1, 0),
            schema,
            stack: Vec::new(),
            documents: Vec::new(),
            anchors: HashMap::new(),
            aliased: 0,
            written: 0,
            tags: Tags {
                str: t("str"),
                int: t("int"),
                float: t("float"),
                bool: t("bool"),
                null: t("null"),
                binary: t("binary"),
                map: t("map"),
                seq: t("seq"),
            },
            error: None,
        }
    }

    fn strukt(&self, module: Atom, keys: &[Atom], values: &[Term<'a>]) -> Term<'a> {
        let mut k = Vec::with_capacity(keys.len() + 1);
        let mut v = Vec::with_capacity(values.len() + 1);
        k.push(atoms::__struct__().encode(self.env));
        v.push(module.encode(self.env));
        k.extend(keys.iter().map(|key| key.encode(self.env)));
        v.extend_from_slice(values);
        Term::map_from_term_arrays(self.env, &k, &v).expect("struct keys are unique")
    }

    fn meta(&self, tag: Term<'a>, mark: Marker) -> Term<'a> {
        let line = mark.line().encode(self.env);
        let column = (mark.col() + 1).encode(self.env);
        self.strukt(
            atoms::meta_struct(),
            &[atoms::tag(), atoms::line(), atoms::column()],
            &[tag, line, column],
        )
    }

    fn collection_tag(&self, tag: Option<&Tag>, default: Term<'a>) -> Term<'a> {
        match tag {
            Some(t) if !is_non_specific(t) => full_tag(t).encode(self.env),
            _ => default,
        }
    }

    fn fail(&mut self, message: String, mark: Marker) {
        if self.error.is_none() {
            self.error = Some((message, mark.line(), mark.col() + 1));
        }
    }

    fn add(&mut self, node: Term<'a>, node_size: usize, anchor: usize, start: Marker) {
        if anchor != 0 {
            self.anchors.insert(anchor, (node, node_size));
        }

        // A sequence starts at the "-" or "[" before its first item; a mapping at its first key,
        // or the "{" or "?" before it
        let first = match self.stack.last() {
            Some(Frame::Seq { items, .. }) if items.is_empty() => {
                self.source.before(start, b"-[").map(Some)
            }
            Some(Frame::Map {
                pairs, key: None, ..
            }) if pairs.is_empty() => Some(Some(self.source.before(start, b"{?").unwrap_or(start))),
            _ => None,
        };
        if let Some(Some(found)) = first {
            match self.stack.last_mut() {
                Some(Frame::Seq { mark, .. } | Frame::Map { mark, .. }) => *mark = found,
                None => {}
            }
        }

        match self.stack.last_mut() {
            None => {
                let document = self.strukt(atoms::document(), &[atoms::root()], &[node]);
                self.documents.push(document);
            }
            Some(Frame::Seq { items, size, .. }) => {
                items.push(node);
                *size += node_size;
            }
            Some(Frame::Map {
                pairs, key, size, ..
            }) => {
                *size += node_size;
                match key.take() {
                    None => *key = Some(node),
                    Some(k) => pairs.push((k, node).encode(self.env)),
                }
            }
        }
    }

    fn scalar(
        &mut self,
        text: &str,
        style: ScalarStyle,
        anchor: usize,
        tag: Option<&Tag>,
        mark: Marker,
    ) {
        match resolve(self.env, &self.tags, self.schema, text, style, tag) {
            Ok((tag, value)) => {
                let meta = self.meta(tag, mark);
                let node = self.strukt(
                    atoms::scalar(),
                    &[atoms::value(), atoms::meta()],
                    &[value, meta],
                );
                self.written += 1;
                self.add(node, 1, anchor, mark);
            }
            Err(message) => self.fail(message, mark),
        }
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
                let tag = self.collection_tag(tag.as_deref(), self.tags.seq);
                self.stack.push(Frame::Seq {
                    items: Vec::new(),
                    size: 1,
                    tag,
                    mark,
                    anchor,
                });
            }
            Event::MappingStart(anchor, tag) => {
                let tag = self.collection_tag(tag.as_deref(), self.tags.map);
                self.stack.push(Frame::Map {
                    pairs: Vec::new(),
                    key: None,
                    size: 1,
                    tag,
                    mark,
                    anchor,
                });
            }
            Event::SequenceEnd => {
                if let Some(Frame::Seq {
                    items,
                    size,
                    tag,
                    mark,
                    anchor,
                }) = self.stack.pop()
                {
                    let meta = self.meta(tag, mark);
                    let count = items.len().encode(self.env);
                    let items = items.encode(self.env);
                    let node = self.strukt(
                        atoms::list(),
                        &[atoms::items(), atoms::meta(), atoms::length()],
                        &[items, meta, count],
                    );
                    self.written += 1;
                    self.add(node, size, anchor, mark);
                }
            }
            Event::MappingEnd => {
                if let Some(Frame::Map {
                    pairs,
                    size,
                    tag,
                    mark,
                    anchor,
                    ..
                }) = self.stack.pop()
                {
                    let meta = self.meta(tag, mark);
                    let pairs = pairs.encode(self.env);
                    let node = self.strukt(
                        atoms::mapping(),
                        &[atoms::pairs(), atoms::meta()],
                        &[pairs, meta],
                    );
                    self.written += 1;
                    self.add(node, size, anchor, mark);
                }
            }
            Event::Alias(id) => match self.anchors.get(&id).copied() {
                Some((node, size)) => {
                    self.aliased += size;
                    if self.aliased > MAX_ALIASED.max(10 * self.written) {
                        self.fail("aliases expand to too many values".to_string(), mark);
                    } else {
                        self.add(node, size, 0, mark);
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
        let mut line_starts = vec![0];
        line_starts.extend(
            text.bytes()
                .enumerate()
                .filter(|&(_, c)| c == b'\n')
                .map(|(i, _)| i + 1),
        );
        Source {
            text: text.as_bytes(),
            line_starts,
            cursor: (1, 0, 0),
        }
    }

    // Byte offset of a 1-indexed line and 0-indexed character column
    fn offset(&mut self, line: usize, col: usize) -> Option<usize> {
        let (cur_line, cur_col, cur_byte) = self.cursor;
        let (mut c, mut byte) = if line == cur_line && col >= cur_col {
            (cur_col, cur_byte)
        } else {
            (0, *self.line_starts.get(line.checked_sub(1)?)?)
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

fn resolve<'a>(
    env: Env<'a>,
    tags: &Tags<'a>,
    schema: Schema,
    text: &str,
    style: ScalarStyle,
    tag: Option<&Tag>,
) -> Result<(Term<'a>, Term<'a>), String> {
    let str = || (tags.str, text.encode(env));

    match tag {
        Some(t) if is_non_specific(t) => Ok(str()),
        Some(t) if t.handle == YAML_TAG => match t.suffix.as_str() {
            "str" => Ok(str()),
            "int" => int(env, text)
                .map(|v| (tags.int, v))
                .ok_or("invalid integer".to_string()),
            "float" => float(env, text)
                .map(|v| (tags.float, v))
                .ok_or("invalid float".to_string()),
            "bool" => bool_any(text)
                .map(|b| (tags.bool, b.encode(env)))
                .ok_or("invalid boolean".to_string()),
            "null" => Ok((tags.null, atoms::nil().encode(env))),
            "binary" => base64(text)
                .map(|b| (tags.binary, bytes(env, &b)))
                .ok_or("invalid binary".to_string()),
            _ => Ok((full_tag(t).encode(env), text.encode(env))),
        },
        Some(t) => Ok((full_tag(t).encode(env), text.encode(env))),
        None if style != ScalarStyle::Plain => Ok(str()),
        None => plain(env, tags, schema, text),
    }
}

fn plain<'a>(
    env: Env<'a>,
    tags: &Tags<'a>,
    schema: Schema,
    text: &str,
) -> Result<(Term<'a>, Term<'a>), String> {
    let null = (tags.null, atoms::nil().encode(env));

    match schema {
        Schema::Failsafe => Ok((tags.str, text.encode(env))),
        Schema::Json => match text {
            "null" | "" => Ok(null),
            "true" => Ok((tags.bool, true.encode(env))),
            "false" => Ok((tags.bool, false.encode(env))),
            _ if json_int(text) => Ok((tags.int, int(env, text).unwrap())),
            _ if json_float(text) => Ok((tags.float, float(env, text).unwrap())),
            _ => Err("invalid plain scalar for the JSON schema".to_string()),
        },
        Schema::Core => match text {
            "" | "~" | "null" | "Null" | "NULL" => Ok(null),
            "true" | "True" | "TRUE" => Ok((tags.bool, true.encode(env))),
            "false" | "False" | "FALSE" => Ok((tags.bool, false.encode(env))),
            _ => Ok(core_number(env, tags, text).unwrap_or((tags.str, text.encode(env)))),
        },
        Schema::Yaml11 => match text {
            "" | "~" | "null" | "Null" | "NULL" => Ok(null),
            _ => match bool_11(text) {
                Some(b) => Ok((tags.bool, b.encode(env))),
                None => Ok(yaml11_number(env, tags, text).unwrap_or((tags.str, text.encode(env)))),
            },
        },
    }
}

fn special_float<'a>(env: Env<'a>, text: &str) -> Option<Term<'a>> {
    match text {
        ".inf" | ".Inf" | ".INF" | "+.inf" | "+.Inf" | "+.INF" => Some(atoms::inf().encode(env)),
        "-.inf" | "-.Inf" | "-.INF" => Some(atoms::neg_inf().encode(env)),
        ".nan" | ".NaN" | ".NAN" => Some(atoms::nan().encode(env)),
        _ => None,
    }
}

// Core: [-+]?[0-9]+, 0o[0-7]+, 0x[0-9a-fA-F]+, and floats with an optional exponent
fn core_number<'a>(env: Env<'a>, tags: &Tags<'a>, text: &str) -> Option<(Term<'a>, Term<'a>)> {
    if let Some(v) = special_float(env, text) {
        return Some((tags.float, v));
    }
    if let Some(digits) = text.strip_prefix("0o") {
        return radix(env, digits, 8, false).map(|v| (tags.int, v));
    }
    if let Some(digits) = text.strip_prefix("0x") {
        return radix(env, digits, 16, false).map(|v| (tags.int, v));
    }
    let (_, body) = sign(text);
    if !body.is_empty() && body.bytes().all(|c| c.is_ascii_digit()) {
        return int(env, text).map(|v| (tags.int, v));
    }
    if core_float(body) {
        return float(env, text).map(|v| (tags.float, v));
    }
    None
}

// YAML 1.1: binary, octal, hex, underscores and base 60, plus floats with underscores
fn yaml11_number<'a>(env: Env<'a>, tags: &Tags<'a>, text: &str) -> Option<(Term<'a>, Term<'a>)> {
    if let Some(v) = special_float(env, text) {
        return Some((tags.float, v));
    }
    let (negative, body) = sign(text);
    if let Some(digits) = body.strip_prefix("0b") {
        return radix(env, digits, 2, negative).map(|v| (tags.int, v));
    }
    if let Some(digits) = body.strip_prefix("0x") {
        return radix(env, digits, 16, negative).map(|v| (tags.int, v));
    }
    if body.len() > 1
        && body.starts_with('0')
        && body.bytes().all(|c| matches!(c, b'0'..=b'7' | b'_'))
    {
        return radix(env, &body[1..], 8, negative).map(|v| (tags.int, v));
    }
    if body.contains(':') {
        return sexagesimal(env, tags, body, negative);
    }
    let digits: String = body.chars().filter(|&c| c != '_').collect();
    let first = body.as_bytes().first().copied();
    if !digits.is_empty() && first != Some(b'_') && digits.bytes().all(|c| c.is_ascii_digit()) {
        let signed = if negative {
            format!("-{digits}")
        } else {
            digits
        };
        return int(env, &signed).map(|v| (tags.int, v));
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
        return float(env, &signed).map(|v| (tags.float, v));
    }
    None
}

// 190:20:30 is 190 * 3600 + 20 * 60 + 30; a fraction on the last part makes it a float
fn sexagesimal<'a>(
    env: Env<'a>,
    tags: &Tags<'a>,
    body: &str,
    negative: bool,
) -> Option<(Term<'a>, Term<'a>)> {
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
        return Some((tags.int, (sign * (whole * 60 + n)).encode(env)));
    }
    let n: f64 = last.parse().ok()?;
    if !(0.0..60.0).contains(&n) || !last.contains('.') {
        return None;
    }
    total += whole as f64 * 60.0 + n;
    Some((tags.float, (sign as f64 * total).encode(env)))
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

fn bool_any(text: &str) -> Option<bool> {
    match text {
        "true" | "True" | "TRUE" => Some(true),
        "false" | "False" | "FALSE" => Some(false),
        _ => bool_11(text),
    }
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
fn int<'a>(env: Env<'a>, text: &str) -> Option<Term<'a>> {
    let text = text.strip_prefix('+').unwrap_or(text);
    match text.parse::<i64>() {
        Ok(i) => Some(i.encode(env)),
        Err(_) => BigInt::parse_bytes(text.as_bytes(), 10).map(|b| b.encode(env)),
    }
}

fn radix<'a>(env: Env<'a>, digits: &str, base: u32, negative: bool) -> Option<Term<'a>> {
    let digits: String = digits.chars().filter(|&c| c != '_').collect();
    let n = BigInt::parse_bytes(digits.as_bytes(), base)?;
    let n = if negative { -n } else { n };
    Some(match i64::try_from(&n) {
        Ok(i) => i.encode(env),
        Err(_) => n.encode(env),
    })
}

fn float<'a>(env: Env<'a>, text: &str) -> Option<Term<'a>> {
    if let Some(v) = special_float(env, text) {
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
        .map(|f| f.encode(env))
}

fn bytes<'a>(env: Env<'a>, data: &[u8]) -> Term<'a> {
    let mut binary = rustler::NewBinary::new(env, data.len());
    binary.as_mut_slice().copy_from_slice(data);
    Term::from(binary)
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
