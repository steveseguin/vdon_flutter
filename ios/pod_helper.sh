#!/bin/bash
# This script uses Homebrew's CocoaPods to avoid RVM Ruby issues

export PATH="/opt/homebrew/opt/ruby/bin:/opt/homebrew/bin:$PATH"
export LANG=en_US.UTF-8
export GEM_HOME="/opt/homebrew/lib/ruby/gems/3.4.0"
export GEM_PATH="/opt/homebrew/lib/ruby/gems/3.4.0"

# Use Homebrew's pod
/opt/homebrew/bin/pod "$@"