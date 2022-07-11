# Change log

## 3.0.3
* Fixed a bug that made it impossible to load additional audio files after the first batch of requests is made.

## 4.0.0
* *Important*: If you were using an older version of elm-audio, you need to update your elm-audio JS code! The latest version can be found [here](https://github.com/MartinSStewart/elm-audio/blob/89147e416dc9ac29333d61b8b96851c0641684cb/src/audio.js) and the minified version is at the bottom of the readme.
* The type signature of update, view, subscriptions, audio have changed. An `AudioData` parameter has been added.
* Added `length` which lets you query `AudioData` for the duration of `Source` sound files.
* Loading audio no longer silently fails.
* `setVolumeAt` no longer causes a runtime error if you set time points in the past.

## 4.0.1
* Fix mistake in documentation

## 4.0.2
* Fix typo in documentation
* Fixed a bug where audio with loopEnd set to a value larger than the audio duration would loop at the end of the audio instead of at the loopEnd time.
* Fixed a bug where changing the loop settings would cause the audio to stop playing.
