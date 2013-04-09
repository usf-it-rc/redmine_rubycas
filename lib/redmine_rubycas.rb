require 'redmine'
require 'casclient'
require 'casclient/frameworks/rails/filter'

module RedmineRubyCas
  extend self

  def plugin
    Redmine::Plugin.find(:redmine_rubycas)
  end

  def settings
    if ActiveRecord::Base.connection.table_exists?(:settings) && self.plugin && Setting.plugin_redmine_rubycas
      Setting.plugin_redmine_rubycas
    else
      plugin.settings[:default]
    end
  end

  def setting(name)
    settings && settings.has_key?(name) && settings[name] || nil
  end

  def enabled?
    setting("enabled") == "true"
  end

  def configure!
    if enabled?
      CASClient::Frameworks::Rails::Filter.configure(
        :cas_base_url => setting("base_url"),
        :login_url => setting("login_url").blank? ? nil : setting("login_url"),
        :logout_url => setting("logout_url").blank? ? nil : setting("logout_url"),
        :validate_url => setting("validate_url").blank? ? nil : setting("validate_url"),
        :username_session_key => setting("username_session_key"),
        :extra_attributes_session_key => setting("extra_attributes_session_key"),
        :logger => Rails.logger
      )
    end
  end

  def extra_attributes_map
    attrs = {}
    setting("auto_user_attributes_map").scan(/((\w+)=(\w+))&?/) do |match|
      redmineAttr = match[1]
      casAttr = match[2]
      attrs[casAttr] = redmineAttr
    end
    attrs
  end

  # Populates standard attributes
  def user_extra_attributes_from_session(session)
    attrs = {}
    map = extra_attributes_map
    if extra_attributes = session[:"#{setting("extra_attributes_session_key")}"]
      extra_attributes.each_pair do |key, val|
        mapped_key = map[key]
        if mapped_key && User.attribute_method?(mapped_key)
          attrs[mapped_key] = (val.is_a? Array) ? val.first : val
        end
      end
    end
    attrs
  end

  # Populates attributes for use as user custom fields
  def user_custom_attributes_from_session(session, user)
    attrs = {}
    fields = {}
    map = extra_attributes_map

    # First, map the key value pairs
    if custom_attributes = session[:"#{setting("extra_attributes_session_key")}"]
      custom_attributes.each_pair do |key,val|
        mapped_key = map[key]
        if mapped_key && !User.attribute_method?(mapped_key)
          attrs[mapped_key] = (val.is_a? Array) ? val.first : val
        end
      end
    end

    # Now, map to the field id
    user.available_custom_fields.each do |field|
      case field.name
      when "namsid"
        fields[field.id] = attrs['namsid']
      when "affiliation"
        fields[field.id] = attrs['affiliation']
      when "campus"
        fields[field.id] = attrs['campus']
      when "college"
        fields[field.id] = attrs['college']
      when "unumber"
        fields[field.id] = attrs['unumber'].to_s.gsub(/[A-Z]/,"")
      end 
    end 
    fields
  end

end
