# frozen_string_literal: true

module Jdpools
  # A user's Entra department lives in user_configs rather than a new users column, so the fork
  # carries no schema migration. UserConfig#value is JSON-serialized; ActiveRecord serializes the
  # value in a where clause too, so queries pass the plain string.
  module Departments
    module_function

    def for(user)
      UserConfig.find_by(user_id: user.id, key: DEPARTMENT_CONFIG_KEY)&.value.presence
    end

    def assign(user, department)
      department = department.to_s.strip.presence

      if department
        UserConfig.find_or_initialize_by(user_id: user.id, key: DEPARTMENT_CONFIG_KEY)
                  .update!(value: department)
      else
        UserConfig.where(user_id: user.id, key: DEPARTMENT_CONFIG_KEY).delete_all
      end
    end

    # Ids of every user whose work this user may see: themself, plus everyone in the same
    # account sharing their department. A blank department sees only their own.
    def visible_user_ids(user)
      department = self.for(user)

      return [user.id] if department.blank?

      ids = UserConfig.joins(:user)
                      .where(key: DEPARTMENT_CONFIG_KEY, value: department)
                      .where(users: { account_id: user.account_id })
                      .pluck(:user_id)

      (ids | [user.id]).sort
    end
  end
end
