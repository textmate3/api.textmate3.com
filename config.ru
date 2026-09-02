require_relative "server"

# Log every incoming request to stderr (puma's direct CLI does not add this
# middleware automatically; rackup used to in development mode).
use Rack::CommonLogger

run Server
