Rails.application.routes.draw do
  # Registers the Devise :user mapping (needed by sign_in/authenticate_user!)
  # without Devise's HTML routes; the API's own auth routes are below.
  devise_for :users, skip: :all

  namespace :api do
    namespace :v1 do
      resource :session, only: %i[create destroy]
      resource :me, only: :show, controller: "me"
      resource :current_membership, only: :show
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
