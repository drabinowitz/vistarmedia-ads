require('chai').use(require('sinon-chai'))

inject    = require 'honk-di'
sinon     = require 'sinon'
{Ajax}    = require 'ajax'
TestAjax  = require 'ajax/test'
Config    = require '../src/config'

global.window =
  document:
    createElement: sinon.stub()
    body:
      appendChild: sinon.stub()
  Cortex:
    getConfig: ->
      undefined
    player:
      mimeTypes: ->
        ['image/png']
  navigator: {}

beforeEach ->
  config = new Config
    'vistar.width':   100
    'vistar.height':  200

  class Binder extends inject.Binder
    configure: ->
      @bind(Ajax).to(TestAjax)
      @bindConstant('config').to(config.all())
      @bindConstant('cortex').to(window.Cortex)
      @bindConstant('navigator').to(global.window.navigator)

  binder    = new Binder
  @injector = new inject.Injector(binder)

afterEach ->
