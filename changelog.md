# Change log

## 3.0.3
* Fixed a bug that made it impossible to additional load audio files after the first batch of requests is made.

## 4.0.0
* The type signature of update, view, subscriptions, audio have changed. An `AudioData` parameter has been added.
* Added `length` which lets you query `AudioData` for the duration of `Source` sound files.
* Loading audio no longer silently fails.
* `setVolumeAt` no longer causes a runtime error if you set time points in the past.
