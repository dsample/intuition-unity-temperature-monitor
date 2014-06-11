#!/usr/bin/env ruby
# encoding: UTF-8

require 'eventmachine'
require 'em-websocket-client'
require 'json'
require 'libnotify'
require 'gtk2'
require 'ruby-libappindicator'

INITIAL_ICON = 'go-home-symbolic'
HOTTER_ICON = 'go-up-symbolic' #'weather-clear-1'
COOLER_ICON = 'go-down-symbolic' #'weather-overcast-1'
SAME_ICON = INITIAL_ICON

class Reading
  attr_accessor :time, :temperature

  def initialize(reading)
    @time = reading['time']
    @temperature = reading['data']['current_temperature']
  end
end

class Processor
  attr_accessor :readings

  def initialize()
  	@readings = []
  end

  def process_heating(data)
    max_readings = 2

    reading = Reading.new data
  	@readings.push reading

    temperature = reading.temperature
    puts "#{reading.time} #{reading.temperature}°C"
    @readings = @readings.drop @readings.length - max_readings if @readings.length > max_readings
  end

  def temperature_movement
    return 0 if @readings.length < 2
    return @readings[1].temperature - @readings[0].temperature
  end

  def getting_hotter?
    #return readings[0] < readings[1] and readings[1] < readings[2] if readings.length == 3
    return temperature_movement > 0
  end

  def getting_cooler?
    return temperature_movement < 0
  end
end

class Notifier
  def self.notify(summary, body)
    Libnotify.show summary: summary, body: body
  end
  def self.notify(summary, body, icon)
    Libnotify.show summary: summary, body: body, icon_path: icon.to_sym
  end
end

EM.run do
  conn = EM::WebSocketClient.connect("ws://192.168.0.110:8080")

  processor = Processor.new

  ai = AppIndicator::AppIndicator.new("temperature", INITIAL_ICON, AppIndicator::Category::OTHER)
  ai.set_menu(Gtk::Menu.new)
  ai.set_status(AppIndicator::Status::ACTIVE)

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

      if processor.getting_hotter?
        Notifier.notify "Temperature", "It's getting hotter!\nWas #{processor.readings[0]}°C now  #{processor.readings[1]}°C", HOTTER_ICON
        ai.set_icon HOTTER_ICON
      elsif processor.getting_cooler?
        ai.set_icon COOLER_ICON
      else
        ai.set_icon SAME_ICON
      end

      menu = Gtk::Menu.new
      processor.readings.each do |r|
        menu.append Gtk::MenuItem.new("#{r.temperature}°C at #{r.time}").show
      end
      ai.set_menu menu

    end
  end

  conn.disconnect do
    puts "Disconnecting"
    EventMachine::stop_event_loop
  end

  give_tick = proc do
    Gtk::main_iteration_do(false)
    EM.next_tick(give_tick)
  end
  give_tick.call


  ['INT','TERM'].each do |sig|
    Signal.trap(sig) do
      EventMachine::stop_event_loop
      EventMachine.stop 
    end
  end
end
