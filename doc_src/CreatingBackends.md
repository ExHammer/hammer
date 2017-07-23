# Creating Backends


See `Hammer.Backend.ETS` for a realistic example of a Hammer Backend module.

The expected backend api is as follows:


### start_link(args)

- `args`: Keyword list of configuration.

The `expiry_ms` and `cleanup_interval_ms` keys are considered essential, as the
backend process should delete expired buckets somehow. Other keys are for the
backend developer to choose, but for example, if the backend were using a
database called `FooDB` to store buckets, then an appropriate key would be
`foodb_config`.

Example:

```elixir
  Hammer.Backend.Foo.start_link(expiry_ms: 60_000 * 60,
                                cleanup_interval_ms: 60_000 * 10,
                                foodb_config: [host: "localhost"])
```

### count_hit(key, timestamp)

- `key`: The key of the current bucket, in the form of a tuple `{bucket::integer, id::String}`.
- `timestamp`: The current timestamp (integer)

This function should increment the count in the bucket by 1.

Returns: Either a Tuple of `{:ok, count}` where count is the current count of the bucket,
or `{:error, reason}`.


### get_bucket(key)

- `key`: The key of the current bucket, in the form of a tuple `{bucket::integer, id::String}`.

Returns: Either a tuple of `{:ok, bucket}`, where `bucket` is a tuple of
`{key, count, created_at, updated_at}`, key is, as usual, a tuple of `{bucket_number, id}`,
`count` is the count of hits in the bucket, `created_at` and `updated_at` are integer timestamps,
or `{:error, reason}`


### delete_buckets(id)

- `id`: rate-limit id (string) to delete

This should delete all existing buckets associated with the supplied `id`.

Returns: Either `{:ok, count}`, or `{:error, reason}`
