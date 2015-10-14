defaultConfig = {}

defaultConfig['vistar.api_key']           = ''
defaultConfig['vistar.network_id']        = ''
defaultConfig['vistar.device_id']         = 'test-device-id'
defaultConfig['vistar.debug']             = false
defaultConfig['vistar.cache_assets']      = true
defaultConfig['vistar.allow_audio']       = false
defaultConfig['vistar.direct_connection'] = false
defaultConfig['vistar.cpm_floor_cents']   = 0
defaultConfig['vistar.ad_buffer_length']  = 8
defaultConfig['vistar.mime_types']        = [
  'image/gif'
  'image/jpg'
  'image/jpeg'
  'image/png'
  'video/webm'
]

defaultConfig['vistar.url'] =
  'http://dev.api.vistarmedia.com/api/v1/get_ad/json'

class Config
  constructor: (@_cortexConfig) ->
    try
      latitude  = Number(@_cortexConfig['vistar.lat'])
      longitude = Number(@_cortexConfig['vistar.lng'])
    catch err
      console.error "Invalid lat/lng: #{latitude}, #{longitude}. \
        err=#{err?.message}"
      latitude  = NaN
      longitude = NaN

    if not isNaN(latitude) and not isNaN(longitude)
      @_cortexConfig['vistar.latitude']  = latitude
      @_cortexConfig['vistar.longitude'] = longitude

    width  = Number(@_cortexConfig['vistar.width'])
    height = Number(@_cortexConfig['vistar.height'])
    if width and height
      @_cortexConfig['vistar.width']  = width
      @_cortexConfig['vistar.height'] = height
    else
      throw new Error "Invalid width/height: \
        #{cortex['vistar.width']}/#{cortex['vistar.height']}"

    @_cortexConfig['vistar.mime_types'] = window.Cortex.player.mimeTypes()

  get: (key) ->
    if key of @_cortexConfig
      @_cortexConfig[key]
    else
      defaultConfig[key]

  all: ->
    url:                     @get 'vistar.url'
    apiKey:                  @get 'vistar.api_key'
    networkId:               @get 'vistar.network_id'
    width:                   @get 'vistar.width'
    height:                  @get 'vistar.height'
    debug:                   @get 'vistar.debug'
    cacheAssets:             @get 'vistar.cache_assets'
    allow_audio:             JSON.parse(@get 'vistar.allow_audio')
    directConnection:        @get 'vistar.direct_connection'
    deviceId:                @get 'vistar.device_id'
    venueId:                 @get 'vistar.venue_id'
    queueSize:               Number(@get 'vistar.ad_buffer_length')
    playlistImplementation:  @get 'vistar.ads.playlist_impl'
    mimeTypes:               @get 'vistar.mime_types'
    latitude:                @get 'vistar.latitude'
    longitude:               @get 'vistar.longitude'
    cpmFloorCents:           @get 'vistar.cpm_floor_cents'
    minDuration:             @get 'vistar.min_duration'
    maxDuration:             @get 'vistar.max_duration'
    rotate:                  JSON.parse(@get 'vistar.rotate')
    displayArea: [
      {
        id:               'display-0'
        width:            @get 'vistar.width'
        height:           @get 'vistar.height'
        allow_audio:      JSON.parse(@get 'vistar.allow_audio')
      }
    ]

module.exports = Config
