defmodule Sensocto.Accounts.User do
  @derive {Jason.Encoder, only: [:id]}
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    otp_app: :sensocto,
    domain: Sensocto.Accounts,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication, AshAdmin.Resource]

  postgres do
    table "users"
    repo Sensocto.Repo
  end

  authentication do
    tokens do
      enabled? true
      token_resource Sensocto.Accounts.Token
      signing_secret Sensocto.Secrets
      store_all_tokens? true
      require_token_presence_for_authentication? true
      # M-001 Security Fix: Reduced token lifetime from 365 days to 14 days.
      # Long-lived tokens increase the risk window if tokens are compromised.
      # 14 days balances security with user convenience for typical usage patterns.
      # Consider implementing refresh tokens for longer sessions if needed.
      token_lifetime {14, :days}
    end

    strategies do
      google do
        # Sensocto.Secrets
        client_id fn _secret, _resource ->
          Application.fetch_env(:sensocto, :google_client_id)
        end

        # Sensocto.Secrets
        # redirect_uri "https://adrians-macbook-pro.local:4001/"
        redirect_uri fn _secret, _resource ->
          Application.fetch_env(:sensocto, :google_redirect_uri)
        end

        # "https://localhost:4001/auth/user/google/callback"
        # Sensocto.Secrets
        client_secret fn _secret, _resource ->
          Application.fetch_env(:sensocto, :google_client_secret)
        end
      end

      # single_use_tokens? false and token_lifetime
      # there isn't like a can_use_tokens_n_times feature is all
      # So if you wanted that, you'd have to turn single_use_tokens? false and add some custom logic

      magic_link do
        identity_field :email
        registration_enabled? true
        token_lifetime 60 * 60
        require_interaction? true

        sender Sensocto.Accounts.User.Senders.SendMagicLinkEmail
      end

      """
      password :password do
        identity_field :email
        hashed_password_field :hashed_password

        resettable do
          sender Sensocto.Accounts.User.Senders.SendPasswordResetEmail
          # these configurations will be the default in a future release
          password_reset_action_name :reset_password_with_token
          request_password_reset_action_name :request_password_reset_token
        end
      end
      """
    end

    add_ons do
      confirmation :confirm_new_user do
        monitor_fields [:email]
        confirm_on_create? true
        confirm_on_update? false
        require_interaction? true

        auto_confirm_actions [
          :sign_in_with_magic_link,
          :reset_password_with_token,
          :register_with_google
        ]

        sender Sensocto.Accounts.User.Senders.SendNewUserConfirmationEmail
      end
    end
  end

  actions do
    defaults [:read, :destroy]

    read :get_by_subject do
      description "Get a user by the subject claim in a JWT"
      argument :subject, :string, allow_nil?: false
      get? true
      prepare AshAuthentication.Preparations.FilterBySubject
    end

    read :get_by_email do
      description "Looks up a user by their email"
      get? true

      argument :email, :ci_string do
        allow_nil? false
      end

      filter expr(email == ^arg(:email))
    end

    create :register_with_google do
      argument :user_info, :map, allow_nil?: false
      argument :oauth_tokens, :map, allow_nil?: false
      upsert? true
      upsert_identity :unique_email

      change AshAuthentication.GenerateTokenChange

      # Required if you have the `identity_resource` configuration enabled.
      # change AshAuthentication.Strategy.OAuth2.IdentityChange

      change fn changeset, _ ->
        user_info = Ash.Changeset.get_argument(changeset, :user_info)

        Ash.Changeset.change_attributes(changeset, Map.take(user_info, ["email"]))
      end

      # Required if you're using the password & confirmation strategies
      upsert_fields []
      change set_attribute(:confirmed_at, &DateTime.utc_now/0)

      change after_action(fn _changeset, user, _context ->
               case user.confirmed_at do
                 nil -> {:error, "Unconfirmed user exists already"}
                 _ -> {:ok, user}
               end
             end)
    end

    create :sign_in_with_magic_link do
      description "Sign in or register a user with magic link."

      argument :token, :string do
        description "The token from the magic link that was sent to the user"
        allow_nil? false
      end

      upsert? true
      upsert_identity :unique_email
      upsert_fields [:email]

      # Uses the information from the token to create or sign in the user
      change AshAuthentication.Strategy.MagicLink.SignInChange

      metadata :token, :string do
        allow_nil? false
      end
    end

    action :request_magic_link do
      argument :email, :ci_string do
        allow_nil? false
      end

      run AshAuthentication.Strategy.MagicLink.Request
    end

    update :change_password do
      # Use this action to allow users to change their password by providing
      # their current password and a new password.

      require_atomic? false
      accept []
      argument :current_password, :string, sensitive?: true, allow_nil?: false
      argument :password, :string, sensitive?: true, allow_nil?: false
      argument :password_confirmation, :string, sensitive?: true, allow_nil?: false

      validate confirm(:password, :password_confirmation)

      validate {AshAuthentication.Strategy.Password.PasswordValidation,
                strategy_name: :password, password_argument: :current_password}

      change {AshAuthentication.Strategy.Password.HashPasswordChange, strategy_name: :password}
    end

    read :sign_in_with_password do
      description "Attempt to sign in using a email and password."
      get? true

      argument :email, :ci_string do
        description "The email to use for retrieving the user."
        allow_nil? false
      end

      argument :password, :string do
        description "The password to check for the matching user."
        allow_nil? false
        sensitive? true
      end

      # validates the provided email and password and generates a token
      prepare AshAuthentication.Strategy.Password.SignInPreparation

      metadata :token, :string do
        description "A JWT that can be used to authenticate the user."
        allow_nil? false
      end
    end

    read :sign_in_with_token do
      # In the generated sign in components, we validate the
      # email and password directly in the LiveView
      # and generate a short-lived token that can be used to sign in over
      # a standard controller action, exchanging it for a standard token.
      # This action performs that exchange. If you do not use the generated
      # liveviews, you may remove this action, and set
      # `sign_in_tokens_enabled? false` in the password strategy.

      description "Attempt to sign in using a short-lived sign in token."
      get? true

      argument :token, :string do
        description "The short-lived sign in token."
        allow_nil? false
        sensitive? true
      end

      # validates the provided sign in token and generates a token
      prepare AshAuthentication.Strategy.Password.SignInWithTokenPreparation

      metadata :token, :string do
        description "A JWT that can be used to authenticate the user."
        allow_nil? false
      end
    end

    create :register_with_password do
      description "Register a new user with a email and password."

      argument :email, :ci_string do
        allow_nil? false
      end

      argument :password, :string do
        description "The proposed password for the user, in plain text."
        allow_nil? false
        constraints min_length: 8
        sensitive? true
      end

      argument :password_confirmation, :string do
        description "The proposed password for the user (again), in plain text."
        allow_nil? false
        sensitive? true
      end

      # Sets the email from the argument
      change set_attribute(:email, arg(:email))

      # Hashes the provided password
      change AshAuthentication.Strategy.Password.HashPasswordChange

      # Generates an authentication token for the user
      change AshAuthentication.GenerateTokenChange

      # validates that the password matches the confirmation
      validate AshAuthentication.Strategy.Password.PasswordConfirmationValidation

      metadata :token, :string do
        description "A JWT that can be used to authenticate the user."
        allow_nil? false
      end
    end

    action :request_password_reset_token do
      description "Send password reset instructions to a user if they exist."

      argument :email, :ci_string do
        allow_nil? false
      end

      # creates a reset token and invokes the relevant senders
      run {AshAuthentication.Strategy.Password.RequestPasswordReset, action: :get_by_email}
    end

    update :reset_password_with_token do
      argument :reset_token, :string do
        allow_nil? false
        sensitive? true
      end

      argument :password, :string do
        description "The proposed password for the user, in plain text."
        allow_nil? false
        constraints min_length: 8
        sensitive? true
      end

      argument :password_confirmation, :string do
        description "The proposed password for the user (again), in plain text."
        allow_nil? false
        sensitive? true
      end

      # validates the provided reset token
      validate AshAuthentication.Strategy.Password.ResetTokenValidation

      # validates that the password matches the confirmation
      validate AshAuthentication.Strategy.Password.PasswordConfirmationValidation

      # Hashes the provided password
      change AshAuthentication.Strategy.Password.HashPasswordChange

      # Generates an authentication token for the user
      change AshAuthentication.GenerateTokenChange
    end

    destroy :delete_user do
      description "Delete a user by their ID."

      argument :id, :uuid do
        allow_nil? false
      end

      filter expr(id == ^arg(:id))
    end

    # Test-only action for creating users without password strategy validation
    # This bypasses AshAuthentication validation that requires password strategy to be enabled
    create :create_test_user do
      description "Create a test user directly (for testing only)"

      argument :email, :ci_string do
        allow_nil? false
      end

      argument :password, :string do
        allow_nil? true
        sensitive? true
      end

      change set_attribute(:email, arg(:email))

      change fn changeset, _context ->
        case Ash.Changeset.get_argument(changeset, :password) do
          nil ->
            changeset

          password ->
            hashed = Bcrypt.hash_pwd_salt(password)
            Ash.Changeset.change_attribute(changeset, :hashed_password, hashed)
        end
      end

      # Auto-confirm test users
      change set_attribute(:confirmed_at, &DateTime.utc_now/0)
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy always() do
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :email, :ci_string do
      allow_nil? false
      public? true
    end

    attribute :hashed_password, :string do
      # allow_nil? false
      allow_nil? true
      sensitive? true
    end
  end

  relationships do
    # Connectors are stored in ETS, not Postgres, so no direct relationship
    # Use Sensocto.Sensors.Connector.list_for_user(user.id) to get user's connectors
  end

  identities do
    identity :unique_email, [:email]
  end
end
