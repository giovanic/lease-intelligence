Rails.application.routes.draw do
  # Registers the Devise :user mapping (needed by sign_in/authenticate_user!)
  # without Devise's HTML routes; the API's own auth routes are below.
  devise_for :users, skip: :all

  namespace :api do
    namespace :v1 do
      resource :session, only: %i[create destroy]
      resource :me, only: :show, controller: "me"
      resource :current_membership, only: :show

      # Portfolio (docs/domain/portfolio.md). No destroy: records are
      # archived through `status`, since leases will reference them.
      resources :properties, only: %i[index show create update]
      resources :counterparties, only: %i[index show create update]

      # Lease Management (docs/domain/leases.md). No destroy: a lease ends
      # through its status (expired/terminated).
      resources :leases, only: %i[index show create update] do
        # Document Management (docs/domain/documents.md). No update/destroy:
        # files are immutable versions (docs/adr/0010).
        resources :documents, only: %i[index show create], controller: "contract_documents" do
          resources :versions, only: :create, controller: "document_versions"
        end
      end

      # File access (docs/adr/0015): a short-lived link is issued after
      # authorization, then the file is served for that link + session.
      resources :document_versions, only: [] do
        resource :download_link, only: :create, controller: "document_download_links"
      end
      get "document_files/:token", to: "document_files#show", as: :document_file,
        constraints: { token: %r{[^/]+} }, format: false
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
