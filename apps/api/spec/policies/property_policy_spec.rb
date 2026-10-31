require "rails_helper"

RSpec.describe PropertyPolicy do
  it_behaves_like "a portfolio record policy", :property
end
