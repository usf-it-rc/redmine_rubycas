module AccountControllerPatch
  def self.included(base)
    base.send(:include, InstanceMethods)
    base.class_eval do
      alias_method_chain :login, :cas
      alias_method_chain :logout, :cas
    end
  end

  module InstanceMethods
    def login_with_cas
      if params[:username].blank? && params[:password].blank? && RedmineRubyCas.enabled?
        if session[:user_id].blank? && CASClient::Frameworks::Rails::Filter.filter(self)
          user = User.find_or_initialize_by_login(session[:"#{RedmineRubyCas.setting("username_session_key")}"])
          if user.new_record?
            if RedmineRubyCas.setting("auto_create_users") == "true"
              attributes = RedmineRubyCas.user_extra_attributes_from_session(session)
              custom_fields = RedmineRubyCas.user_custom_attributes_from_session(session, user)

              Rails.logger.debug "login_with_cas() => attributes = " + attributes.to_s 
              Rails.logger.debug "login_with_cas() => custom_fields = " + custom_fields.to_s 

              # Use namsid to set user id, if available (USF-centric)
              if custom_fields.has_key?(2)
                user.id = custom_fields[2]
              end

              # set default mail address if mail is empty
              if !attributes.has_key?(:mail) or attributes[:mail] == nil
                attributes[:mail] = session[:"#{RedmineRubyCas.setting("username_session_key")}"] + "@" + RedmineRubyCas.setting("fallback_email_domain")
              end

              user.attributes = attributes
              user.custom_field_values = custom_fields
              user.status = User::STATUS_REGISTERED
              user.activate
              user.last_login_on = Time.now

              if user.save
                self.logged_user = user
                flash[:notice] = l(:notice_account_activated)
                redirect_to '/'
              else
                onthefly_creation_failed(user)
              end
            else
              render_error(
                :message => l(:cas_user_not_found, :user => session[:"#{RedmineRubyCas.setting("username_session_key")}"]),
                :status => 401
              )
            end
          else
            if user.active?
              if RedmineRubyCas.setting("auto_update_users") == "true"
                user.update_attributes(RedmineRubyCas.user_extra_attributes_from_session(session))
                user.custom_field_values = RedmineRubyCas.user_custom_attributes_from_session(session,user)
                user.save
              end

              logger.info "Successful authentication for '#{user.login}' from #{request.remote_ip} at #{Time.now.utc}"
              # Valid user
              self.logged_user = user
              # generate a key and set cookie if autologin
              if params[:autologin] && Setting.autologin?
                set_autologin_cookie(user)
              end 
              call_hook(:controller_account_success_authentication_after, {:user => user })
              redirect_back_or_default "/"

              #successful_authentication(user)
            else
              render_error(
                :message => l(:cas_user_not_found, :user => session[:"#{RedmineRubyCas.setting("username_session_key")}"]),
                :status => 401
              )
            end
          end
        end
      else
        login_without_cas
      end
    end

    def logout_with_cas
      if RedmineRubyCas.enabled? && RedmineRubyCas.setting("logout_of_cas_on_logout") == "true"
        CASClient::Frameworks::Rails::Filter.logout(self, home_url)
        logout_user
      else
        logout_without_cas
      end
    end
  end
end
