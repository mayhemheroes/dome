// Encapsulates the data of the currently playing channel
foreign class AudioChannel {
  construct new(id, audio) {}
  foreign isFinished
  foreign id
}

// Represents the data of an audio file
// which can be loaded and unloaded
// It is otherwise opaque Wren-side
foreign class AudioData {
  construct fromFile(path) {}
  foreign unload()
}

foreign class AudioEngineImpl {
  construct init() {
    __files = {}
    __playing = []
    __channels = {}
    __newChannelId = 42
  }
  // TODO: Allow device enumeration and selection

  // Loading and unloading
  // We only support loading WAV and (maybe) OGG
  load(name, path) {
    if (!__files.containsKey(name)) {
      __files[name] = AudioData.fromFile(path)
    }

    return __files[name]
  }
  unload(name) {
    if (__files.containsKey(name)) {
      __files[name] = null
    }
  }
  unloadAll() {
    __files = {}
  }

  // audio mix operations
  play(name) { play(name, 0.5, 0) }
  play(name, volume) {}
  play(name, volume, pan) {
    if (__files.containsKey(name)) {
      var channel = AudioChannel.new(__newChannelId, __files[name])
      __playing.add(channel)
      __channels[__newChannelId] = channel
      __newChannelId = __newChannelId + 1
    }
  }

  stopChannel(channelId) {}
  setChannelVolume(channelId, volume) {}
  setChannelPan(channelId, pan) {}
  stopAllChannels() {}
  isPlaying(channelId) { }

  update() {
    __playing = __playing.where {|channel|
      var finished = !channel.isFinished
      if (finished) {
        __channels[channel.id] = null
      }
      return finished
    }.toList
    f_update(__playing)
    System.gc()
    // __playing = []
  }
  foreign f_update(list)
}

// We only intend to expose this
var AudioEngine = AudioEngineImpl.init()
