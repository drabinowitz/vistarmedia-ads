inject        = require 'honk-di'
{Ajax}        = require 'ajax'
{XMLHttpAjax} = require 'ajax'
View          = require './view'
Config        = require './config'

init = ->
  window.addEventListener 'cortex-ready', ->
    window.Cortex.app.getConfig()
      .then (config) ->
        appConfig = new Config config
        class Binder extends inject.Binder
          configure: ->
            @bind(Ajax).to(XMLHttpAjax)
            @bindConstant('config').to(appConfig.all())
            @bindConstant('cortex').to(window.Cortex)
            @bindConstant('navigator').to(window.navigator)

        injector = new inject.Injector(new Binder)
        window.VistarAdView = injector.getInstance View
        window.Cortex.app.registerHealthCheck window.VistarAdView.healthCheck
        window.Cortex.scheduler.onPrepare window.VistarAdView.prepare

      .catch (e) ->
        console.error 'Failed to initialize the application.', e
        console.error e
        throw e

module.exports = init()
