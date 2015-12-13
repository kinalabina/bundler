require "bundler/fetcher/base"
require "cgi"

module Bundler
  class Fetcher
    class Dependency < Base
      def available?
        fetch_uri.scheme != "file" && downloader.fetch(dependency_api_uri)
      rescue NetworkDownError => e
        raise HTTPError, e.message
      rescue AuthenticationRequiredError
        # We got a 401 from the server. Just fail.
        raise
      rescue HTTPError
      end

      def api_fetcher?
        true
      end

      def specs(gem_names, full_dependency_list = [], last_spec_list = [])
        query_list = gem_names.uniq - full_dependency_list

        # only display the message on the first run
        if Bundler.ui.debug?
          Bundler.ui.debug "Query List: #{query_list.inspect}"
        else
          Bundler.ui.info ".", false
        end

        if query_list.empty?
          return last_spec_list.map do |args|
            EndpointSpecification.new(*args)
          end
        end

        remote_specs = Bundler::Retry.new("dependency api", AUTH_ERRORS).attempts do
          dependency_specs(query_list)
        end

        spec_list, deps_list = remote_specs
        returned_gems = spec_list.map(&:first).uniq
        specs(deps_list, full_dependency_list + returned_gems, spec_list + last_spec_list)
      rescue HTTPError, MarshalError, GemspecError
        Bundler.ui.info "" unless Bundler.ui.debug? # new line now that the dots are over
        Bundler.ui.debug "could not fetch from the dependency API, trying the full index"
        return nil
      end

      def dependency_specs(gem_names)
        Bundler.ui.debug "Query Gemcutter Dependency Endpoint API: #{gem_names.join(",")}"
        gem_list = []

        gem_names.each_slice(Source::Rubygems::API_REQUEST_SIZE) do |names|
          marshalled_deps = downloader.fetch(dependency_api_uri(names)).body
          gem_list.push(*Bundler.load_marshal(marshalled_deps))
        end

        deps_list = []
        spec_list = []

        gem_list.each do |s|
          deps_list.push(*s[:dependencies].keys)
          spec_list.push([s[:name], s[:number], s[:platform], s[:dependencies]])
        end

        [spec_list, deps_list]
      end

      def dependency_api_uri(gem_names = [])
        uri = fetch_uri + "api/v1/dependencies"
        uri.query = "gems=#{CGI.escape(gem_names.join(","))}" if gem_names.any?
        uri
      end

    end
  end
end
