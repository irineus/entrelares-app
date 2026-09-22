# T-79 — the store pipeline's only tool. fastlane was chosen over a
# single-purpose upload action because the SAME tool covers the future iOS
# channel (T-40): `pilot` → TestFlight, `deliver` → App Store, `match` for
# signing. Pinned exactly: a store upload is not the place to meet a new major.
source "https://rubygems.org"

gem "fastlane", "2.240.1"

plugins_path = File.join(File.dirname(__FILE__), "fastlane", "Pluginfile")
eval_gemfile(plugins_path) if File.exist?(plugins_path)
