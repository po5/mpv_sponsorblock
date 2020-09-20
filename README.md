# mpv_sponsorblock
A fully-featured port of [SponsorBlock](https://github.com/ajayyy/SponsorBlock) for mpv.

## Requirements
- Python 3

## Installation
Move this repo's contents into your mpv `scripts` folder.

## Usage
Play a YouTube video, sponsors will be skipped automatically.

Default key bindings:
- g to set segment boundaries
- G (shift+g) to submit a segment
- h to upvote the last segment
- H (shift+h) to downvote the last segment

These can be remapped with the following script bindings: `sponsorblock/set_segment`, `sponsorblock/submit_segment`, `sponsorblock/upvote_segment`, `sponsorblock/downvote_segment`

Add lines in the following format to your input.conf: `alt+g script-binding sponsorblock/set_segment`