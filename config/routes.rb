require 'sidekiq/web'
require 'admin_constraint'

Rails.application.routes.draw do
  mount Sidekiq::Web => '/sidekiq', constraints: AdminConstraint.new
  mount Blazer::Engine, at: "blazer", constraints: AdminConstraint.new
  get '/sidekiq', to: 'users#auth' # fallback if adminconstraint fails, meaning user is not signed in

  root to: 'static_pages#index'
  get 'stats', to: 'static_pages#stats'
  get 'deprecated', to: 'static_pages#deprecated' # deprecated index page

  resources :users, only: [:edit, :update] do
    collection do
      get 'impersonate', to: 'users#impersonate'
      get 'auth', to: 'users#auth'
      post 'login_code', to: 'users#login_code'
      post 'exchange_login_code', to: 'users#exchange_login_code'
      delete 'logout', to: 'users#logout'

      # sometimes users refresh the login code page and get 404'd
      get 'exchange_login_code', to: redirect('/users/auth', status: 301)
      get 'login_code', to: redirect('/users/auth', status: 301)
    end
    post 'delete_profile_picture', to: 'users#delete_profile_picture'
    patch 'stripe_cardholder_profile', to: 'stripe_cardholders#update_profile'
  end

  # webhooks
  post 'webhooks/donations', to: 'donations#accept_donation_hook'

  resources :organizer_position_invites, only: [:index, :show], path: 'invites' do
    post 'accept'
    post 'reject'
    post 'cancel'
  end

  resources :organizer_positions, only: [:destroy], as: 'organizers' do
    resources :organizer_position_deletion_requests, only: [:new], as: 'remove'
  end

  resources :organizer_position_deletion_requests, only: [:index, :show, :create] do
    post 'close'
    post 'open'

    resources :comments
  end

  resources :g_suite_applications, except: [:new, :create, :edit, :update] do
    post 'accept'
    post 'reject'

    resources :comments
  end

  resources :g_suite_accounts, only: [:index, :create, :update, :edit, :destroy], path: 'g_suite_accounts' do
    put 'reset_password'
    put 'toggle_suspension'
    get 'verify', to: 'g_suite_account#verify'
    post 'reject'
  end

  resources :g_suites, except: [:new, :create, :edit, :update] do
    resources :g_suite_accounts, only: [:create]

    resources :comments
  end

  resources :sponsors

  resources :invoices, only: [:show] do
    collection do
      get '', to: 'invoices#all_index', as: :all
    end
    get 'manual_payment'
    post 'manually_mark_as_paid'
    post 'archive'
    post 'unarchive'
    resources :comments
  end

  resources :stripe_cardholders, only: [:new, :create, :update]
  resources :stripe_cards, only: %i[create new index show]
  resources :emburse_cards do
    post 'toggle_active'
  end

  resources :checks, only: [:show, :index, :edit, :update] do
    collection do
      get 'export'
    end
    get 'view_scan'

    get 'start_approval'
    post 'approve'
    post 'reject'
    get 'start_void'
    post 'void'
    get 'refund', to: 'checks#refund_get'
    post 'refund', to: 'checks#refund'

    resources :comments
  end

  resources :ach_transfers, only: [:show, :index] do
    get 'start_approval'
    post 'approve'
    post 'reject'

    resources :comments
  end

  resources :disbursements, only: [:index, :new, :create, :show, :edit, :update] do
    post 'mark_fulfilled'
    post 'reject'
  end

  resources :comments, only: [:edit, :update]

  resources :documents, except: [:index] do
    collection do
      get '', to: 'documents#common_index', as: :common
    end
    get 'download'
  end

  resources :bank_accounts, only: [:new, :create, :update, :show, :index] do
    get 'reauthenticate'
  end

  resources :transactions, only: [:index, :show, :edit, :update] do
    collection do
      get 'export'
    end
    resources :comments
  end

  resources :fee_reimbursements, only: [:index, :show, :edit, :update] do
    collection do
      get 'export'
    end
    post 'mark_as_processed'
    resources :comments
  end

  get 'pending_fees', to: 'static_pages#pending_fees'
  get 'export_pending_fees', to: 'static_pages#export_pending_fees'
  get 'pending_disbursements', to: 'static_pages#pending_disbursements'
  get 'export_pending_disbursements', to: 'static_pages#export_pending_disbursements'

  get 'branding', to: 'static_pages#branding'
  get 'faq', to: 'static_pages#faq'

  resources :emburse_card_requests, path: 'emburse_card_requests' do
    collection do
      get 'export'
    end
    post 'reject'
    post 'cancel'

    resources :comments
  end

  resources :emburse_transfers, except: [:new] do
    collection do
      get 'export'
    end
    post 'accept'
    post 'reject'
    post 'cancel'
    resources :comments
  end

  resources :emburse_transactions, only: [:index, :edit, :update, :show] do
    resources :comments
  end

  resources :donations, only: [:show] do
    collection do
      get '', to: 'donations#all_index', as: :all
      get 'start/:event_name', to: 'donations#start_donation', as: 'start_donation'
      post 'start/:event_name', to: 'donations#make_donation', as: 'make_donation'
      get 'qr/:event_name.png', to: 'donations#qr_code', as: 'qr_code'
      get ':event_name/:donation', to: 'donations#finish_donation', as: 'finish_donation'
    end
  end

  # api
  get  'api/v1/events/find', to: 'api#event_find'
  post 'api/v1/events', to: 'api#event_new'
  post 'api/v1/disbursements', to: 'api#disbursement_new'

  post 'stripe/webhook', to: 'stripe#webhook'

  post 'export/finances', to: 'exports#financial_export'

  get 'pending_fees', to: 'static_pages#pending_fees'
  get 'negative_events', to: 'static_pages#negative_events'

  get 'admin_tasks', to: 'static_pages#admin_tasks'
  get 'admin_task_size', to: 'static_pages#admin_task_size'
  get 'admin_search', to: 'static_pages#search'
  post 'admin_search', to: 'static_pages#search'

  resources :ops_checkins, only: [:create]

  get '/integrations/frankly' => 'integrations#frankly'

  post '/events' => 'events#create'
  get '/events' => 'events#index'
  get '/event_by_airtable_id/:airtable_id' => 'events#by_airtable_id'
  resources :events, path: '/' do
    get 'team', to: 'events#team', as: :team
    get 'g_suite', to: 'events#g_suite_overview', as: :g_suite_overview
    put 'g_suite_verify', to: 'events#g_suite_verify', as: :g_suite_verify
    get 'emburse_cards', to: 'events#emburse_card_overview', as: :emburse_cards_overview
    get 'cards', to: 'events#card_overview', as: :cards_overview
    get 'stripe_cards/new', to: 'stripe_cards#new'

    get 'transfers', to: 'events#transfers', as: :transfers
    get 'promotions', to: 'events#promotions', as: :promotions
    get 'reimbursements', to: 'events#reimbursements', as: :reimbursements
    get 'donations', to: 'events#donation_overview', as: :donation_overview
    resources :checks, only: [:new, :create]
    resources :ach_transfers, only: [:new, :create]
    resources :organizer_position_invites,
              only: [:new, :create],
              path: 'invites'
    resources :g_suites, only: [:new, :create, :edit, :update]
    resources :g_suite_applications, only: [:new, :create, :edit, :update]
    resources :emburse_transfers, only: [:new]
    resources :documents, only: [:index]
    get 'fiscal_sponsorship_letter', to: 'documents#fiscal_sponsorship_letter'
    resources :invoices, only: [:new, :create, :index]
  end

  # rewrite old event urls to the new ones not prefixed by /events/
  get '/events/*path', to: redirect('/%{path}', status: 302)

  # Beware: Routes after "resources :events" might be overwritten by a
  # similarly named event
end
