#!/usr/bin/env bash
# gh-stub.sh - a small simulator of the project board for test_archive-done.sh (used as `gh`).
# State: $STUB_DIR/board.json {options, items}. Logs every request to $STUB_DIR/requests.log.
# Real behaviour it copies: removing a column that holds issues clears their Status.
# Switches: STUB_NOBOARD=1 no linked board, STUB_STALE=1 moves are accepted but do nothing,
# STUB_CLOSE=1 a move changes the state of the issue (the built-in workflow of the spike),
# STUB_PAGE=<n> page size of the items.
dir=${STUB_DIR:?}
args="$*"
board="$dir/board.json"
printf '%s\n----\n' "$args" >> "$dir/requests.log"

if [[ "$args" == *"--input"* ]]; then
    body=$(cat)
    printf '%s\n----\n' "$body" >> "$dir/requests.log"
    jq -c '.variables.input.singleSelectOptions | map(. + {id: (.id // ("NEW_" + .name))})' <<<"$body" > "$dir/options.json"
    jq -c --slurpfile o "$dir/options.json" '.options = $o[0] | .items |= map(if (.status as $s | $o[0] | map(.name) | index($s)) then . else .status = null end)' "$board" > "$dir/b.tmp" && mv "$dir/b.tmp" "$board"
    jq -c '{data:{updateProjectV2Field:{projectV2Field:{options: .}}}}' "$dir/options.json"
    exit 0
fi
if [[ "$args" == *"updateProjectV2ItemFieldValue"* ]]; then
    if [ -z "${STUB_STALE:-}" ]; then
        pairs=$(grep -o 'itemId: "[^"]*"\|singleSelectOptionId: "[^"]*"' <<<"$args" | sed 's/.*: "//; s/"$//' | paste -d' ' - -)
        while read -r item opt; do
            jq -c --arg i "$item" --arg o "$opt" --arg c "${STUB_CLOSE:-}" '(.options | map(select(.id == $o)) | first | .name) as $n
                | .items |= map(if .id == $i then (.status = $n | if $c != "" then .state = "OPEN" else . end) else . end)' "$board" > "$dir/b.tmp" && mv "$dir/b.tmp" "$board"
        done <<<"$pairs"
    fi
    echo '{"data":{}}'
    exit 0
fi
if [[ "$args" == *"projectsV2("* ]]; then
    if [ -n "${STUB_NOBOARD:-}" ]; then echo '{"data":{"repository":{"projectsV2":{"nodes":[]}}}}'; exit 0; fi
    jq -c '{data:{repository:{projectsV2:{nodes:[{id:"P1", number:1, field:{id:"F1", options: .options}}]}}}}' "$board"
    exit 0
fi
if [[ "$args" == *"node(id"* ]]; then
    after=$(grep -o 'after:"[^"]*"' <<<"$args" | sed 's/.*:"//; s/"$//')
    jq -c --argjson size "${STUB_PAGE:-100}" --argjson from "${after:-0}" '.items as $all | ($all[$from:$from + $size]) as $page | {data:{node:{items:{
        pageInfo:{hasNextPage: ($from + $size < ($all | length)), endCursor: (($from + $size) | tostring)},
        nodes: ($page | map({id, content: (if .issue then {number: .issue, state, closedAt} else {} end),
            fieldValues:{nodes:[{name: .status, field:{name:"Status"}}, {date: .endDate, field:{name:"End date"}}]}}))}}}}' "$board"
    exit 0
fi
echo "stub gh: unexpected call: $args" >&2
exit 99
