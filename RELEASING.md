# Releasing

1. Set the new version in `mix.exs`, rename `Unreleased` in `CHANGELOG.md` to it with the date,
   and update the version in the `README.md` install line. Merge this to `main`.

2. Tag `main` with the version and push the tag:

   ```sh
   git tag v0.4.0
   git push origin v0.4.0
   ```

   The "Build precompiled NIFs" workflow builds the parser for every platform and attaches the
   builds to the `v0.4.0` GitHub release.

3. When every job has passed, download the builds to write their checksums, and commit the file:

   ```sh
   mix rustler_precompiled.download YAML.Native --all --print
   git add checksum-Elixir.YAML.Native.exs
   ```

4. Publish to Hex, and check that the printed file list has `checksum-Elixir.YAML.Native.exs`
   and no `priv/native` files:

   ```sh
   MIX_ENV=docs mix hex.publish
   ```
