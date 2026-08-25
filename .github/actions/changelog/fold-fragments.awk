# fold-fragments.awk — merge changelog.d fragment groups into one section of
# a Keep-a-Changelog file. Invoked by _lib/changelog-fragments.sh:
#   awk -v version=X.Y.Z -v fragdir=/tmp/... -v canon="added changed ..." \
#     -f fold-fragments.awk CHANGELOG.md
# fragdir holds one file per section heading ("Security", "Added", …) with
# the fragments' content lines. Groups already in the section keep their
# order and gain the matching file's lines; sections without a group are
# appended in canonical order. One blank line between groups, exactly.
# The whole file passes through; only the [version] section is rewritten.

function fragfile(heading) {
  return fragdir "/" heading
}

function have_fragments(heading,   line, found) {
  # getline-from-file advances the position; close so emit reads from the top.
  found = (getline line < fragfile(heading)) > 0
  close(fragfile(heading))
  return found
}

function emit_fragments(heading,   line) {
  while ((getline line < fragfile(heading)) > 0) print line
  close(fragfile(heading))
}

function flush(  i, s, out) {
  for (i = 0; i < npream; i++) print pre[i]
  for (i = 1; i <= ngroups; i++) {
    s = order[i]
    print ""
    print "### " s
    print ""
    out = body[s]
    sub(/^\n+/, "", out)
    sub(/\n+$/, "", out)
    if (out != "") print out
    if (have_fragments(s)) emit_fragments(s)
  }
  for (i = 1; i <= ncanon; i++) {
    s = canon_title[i]
    if (!(s in seen) && have_fragments(s)) {
      print ""
      print "### " s
      print ""
      emit_fragments(s)
    }
  }
  print ""
}

BEGIN {
  ncanon = split(canon, clist, " ")
  for (i = 1; i <= ncanon; i++) {
    w = clist[i]
    canon_title[i] = toupper(substr(w, 1, 1)) substr(w, 2)
  }
  in_section = 0
  ngroups = 0
  cur = ""
  npream = 0
}

$0 ~ "^## \\[" version "\\]" {
  in_section = 1
  print
  next
}

in_section && (/^## / || /^\[[^]]+\]: /) {
  flush()
  in_section = 0
  print
  next
}

in_section && /^### / {
  cur = substr($0, 5)
  if (!(cur in seen)) { seen[cur] = 1; order[++ngroups] = cur }
  next
}

in_section {
  if (cur == "") {
    if ($0 ~ /[^[:space:]]/) pre[npream++] = $0
  } else {
    body[cur] = body[cur] $0 "\n"
  }
  next
}

{ print }

END { if (in_section) flush() }
