#!/usr/bin/env ruby
# encoding: UTF-8

require 'eventmachine'
require 'em-websocket-client'
require 'json'
require 'libnotify'

class Processor
  attr_accessor :readings

  def initialize()
  	@readings = []

  end

  def process_heating(reading)
    max_readings = 2

    reading = reading
    temperature = reading['data']['current_temperature']
  	@readings.push temperature
    puts "#{reading['time']} #{temperature}°C"
    @readings = @readings.drop @readings.length - max_readings if @readings.length > max_readings
  end

  def getting_hotter?
    #return readings[0] < readings[1] and readings[1] < readings[2] if readings.length == 3
    return @readings.length >= 2 && @readings[0] < @readings[1]
  end
end

class Notifier
  def self.notify(summary, body)
    Libnotify.show summary: summary, body: body
  end
end

EM.run do
  conn = EM::WebSocketClient.connect("ws://192.168.0.110:8080")

  processor = Processor.new

  conn.callback do
    puts "Connected"
  end

  conn.errback do |e|
    puts "Got error: #{e}"
  end

  conn.stream do |msg|
    reading = JSON.parse msg.data
    #puts "stream: #{reading['type']}: #{msg}" if reading['type'].downcase == 'heating'

    if reading['type'].downcase == 'heating'
      processor.process_heating reading
      Notifier.notify "Temperature", "It's getting hotter!\nWas #{processor.readings[0]}°C now  #{processor.readings[1]}°C" if processor.getting_hotter?
    end
  end

  conn.disconnect do
    puts "Disconnecting"
    EventMachine::stop_event_loop
  end


  ['INT','TERM'].each do |sig|
    Signal.trap(sig) do
      EventMachine::stop_event_loop
      EventMachine.stop 
    end
  end
end