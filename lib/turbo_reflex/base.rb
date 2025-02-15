# frozen_string_literal: true

# TurboReflex base superclass.
# All TurboReflex classes should inherit from this class.
#
# Reflexes are executed via a before_action in the Rails controller lifecycle.
# They have access to the following methods and properties.
#
# * dom_id ...................... The Rails dom_id helper
# * dom_id_selector ............. Returns a CSS selector for a dom_id
# * controller .................. The Rails controller processing the HTTP request
# * element ..................... A struct that represents the DOM element that triggered the reflex
# * morph ....................... Appends a Turbo Stream to morph a DOM element
# * params ...................... Reflex specific params (frame_id, element, etc.)
# * render ...................... Renders Rails templates, partials, etc. (doesn't halt controller request handling)
# * render_response ............. Renders a full controller response
# * renderer .................... An ActionController::Renderer
# * prevent_controller_action ... Prevents the rails controller/action from running (i.e. the reflex handles the response entirely)
# * turbo_stream ................ A Turbo Stream TagBuilder
# * turbo_streams ............... A list of Turbo Streams to append to the response (also aliased as streams)
# * state ....................... An object that stores ephemeral `state`
#
class TurboReflex::Base
  class << self
    def preventers
      @preventers ||= Set.new
    end

    def prevent_controller_action(options = {})
      preventers << options.with_indifferent_access
    end

    def should_prevent_controller_action?(reflex, method_name)
      method_name = method_name.to_s
      match = preventers.find do |options|
        only = options[:only] || []
        only = [only] unless only.is_a?(Array)
        only.map!(&:to_s)

        except = options[:except] || []
        except = [except] unless except.is_a?(Array)
        except.map!(&:to_s)

        options.blank? || only.include?(method_name) || (except.present? && except.exclude?(method_name))
      end

      return false if match.nil?

      if match[:if].present?
        case match[:if]
        when Symbol then reflex.public_send(match[:if])
        when Proc then reflex.instance_exec { match[:if].call reflex }
        end
      elsif match[:unless].present?
        case match[:unless]
        when Symbol then !reflex.public_send(match[:unless])
        when Proc then !(reflex.instance_exec { match[:unless].call(reflex) })
        end
      else
        true
      end
    end
  end

  attr_reader :controller, :turbo_streams
  alias_method :streams, :turbo_streams

  delegate :dom_id, :render, to: :"controller.view_context"
  delegate(
    :controller_action_prevented?,
    :render_response,
    :turbo_stream,
    :state,
    to: :@runner
  )

  def initialize(runner)
    @runner = runner
    @controller = runner.controller
    @turbo_streams = Set.new
  end

  def dom_id_selector(...)
    "##{dom_id(...)}"
  end

  def morph(selector, html)
    turbo_streams << turbo_stream.invoke("morph", args: [html], selector: selector)
  end

  # default reflex invoked when method not specified
  def noop
  end

  def params
    @runner.reflex_params
  end

  def element
    @element ||= begin
      attributes = params[:element_attributes]
      attrs = attributes.keys.each_with_object({}) do |key, memo|
        memo[:aria] ||= {}
        memo[:dataset] ||= {}
        if key.start_with?("data_")
          memo[:dataset][key[5..].parameterize.underscore.to_sym] = attributes[key]
        elsif key.start_with?("aria_")
          memo[:aria][key[5..].parameterize.underscore.to_sym] = attributes[key]
        else
          memo[key.parameterize.underscore.to_sym] = attributes[key]
        end
      end
      attrs[:aria] = OpenStruct.new(attrs[:aria])
      attrs[:dataset] = OpenStruct.new(attrs[:dataset])
      OpenStruct.new attrs
    end
  end

  def should_prevent_controller_action?(method_name)
    self.class.should_prevent_controller_action? self, method_name
  end
end
