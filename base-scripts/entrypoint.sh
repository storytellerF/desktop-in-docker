#!/bin/bash

echo "Current user: $(whoami)"

TOTAL=$(find /home/$(whoami) -print0 | tr -cd '\0' | wc -c)
echo "$TOTAL files"

find /home/$(whoami) -print0 \
| tr '\0' '\n' \
| pv -l -s "$TOTAL" \
| while IFS= read -r file; do
    sudo chown $(whoami):$(whoami) "$file"
  done

# inject point

# Start supervisor
./bin/start-supervisord.sh