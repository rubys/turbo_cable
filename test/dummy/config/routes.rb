Rails.application.routes.draw do
  mount TurboCable::Engine => "/turbo_cable"
end
