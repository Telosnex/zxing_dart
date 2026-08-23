#!/bin/bash
# Open package:test's loopback manager URL directly. Modern Safari asks for an
# interactive confirmation when package:test's temporary local redirect file
# is opened, preventing unattended runs.
set -euo pipefail

if [[ ${#} -ne 1 ]]; then
  echo "Usage: $0 package-test-redirect.html" >&2
  exit 64
fi
redirect_path=$1
[[ -f "$redirect_path" ]] || exit 66
redirect_html=$(<"$redirect_path")
prefix='<script>location = "'
suffix='"</script>'
if [[ "$redirect_html" != "$prefix"*"$suffix" ]]; then
  echo "Unexpected package:test Safari redirect contents." >&2
  exit 65
fi
test_url=${redirect_html#"$prefix"}
test_url=${test_url%"$suffix"}
case "$test_url" in
  http://localhost:* | http://127.0.0.1:* | http://\[::1\]:*) ;;
  *) echo "Refusing non-loopback URL: $test_url" >&2; exit 65 ;;
esac
/usr/bin/open -a Safari "$test_url"

cleaned_up=false
cleanup() {
  [[ "$cleaned_up" == true ]] && return
  cleaned_up=true
  /usr/bin/osascript - "$test_url" <<'APPLESCRIPT' >/dev/null 2>&1 || true
on run argv
  set testURL to item 1 of argv
  tell application "Safari"
    repeat with windowIndex from (count of windows) to 1 by -1
      set safariWindow to window windowIndex
      repeat with tabIndex from (count of tabs of safariWindow) to 1 by -1
        set safariTab to tab tabIndex of safariWindow
        try
          if (URL of safariTab) starts with testURL then close safariTab
        end try
      end repeat
    end repeat
  end tell
end run
APPLESCRIPT
}
trap 'cleanup; exit 0' HUP INT TERM
trap cleanup EXIT
while true; do sleep 1; done
