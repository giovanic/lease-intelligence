require "rails_helper"

RSpec.describe LeasePolicy do
  it_behaves_like "a portfolio record policy", :lease
end
