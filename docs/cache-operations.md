# Cache operations

GitHub grants each repository 10 GB of Actions cache by default and removes entries not accessed for seven days.
Target entries pile up, one per `Cargo.lock` state plus pull-request duplicates only the same pull request can restore, so an occasional look pays off.

Inventory, largest first:

```sh
gh cache list -R <owner>/<repo> --limit 100 \
  --json key,sizeInBytes,ref,lastAccessedAt \
  --jq 'sort_by(-.sizeInBytes)[] | "\(.sizeInBytes/1048576|floor) MB  \(.ref)  \(.key)"'
```

Delete superseded default-branch generations of one family, keeping the newest:

```sh
gh cache list -R <owner>/<repo> --ref refs/heads/main \
  --json id,key,createdAt \
  --jq '[.[] | select(.key | startswith("<prefix>-"))] | sort_by(.createdAt) | .[:-1][].id' \
  | xargs -rn1 gh cache delete -R <owner>/<repo>
```

Drop a pull request's leftovers:

```sh
gh cache list -R <owner>/<repo> --ref refs/pull/<n>/merge --json id --jq '.[].id' \
  | xargs -rn1 gh cache delete -R <owner>/<repo>
```
