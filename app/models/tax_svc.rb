require 'json'
require 'net/http'
require 'addressable/uri'
require 'base64'
require 'logging'

# Avatax tax calculation API calls
class TaxSvc
  AVALARA_OPEN_TIMEOUT = ENV.fetch('AVALARA_OPEN_TIMEOUT', 2)
  AVALARA_READ_TIMEOUT = ENV.fetch('AVALARA_READ_TIMEOUT', 6)
  AVALARA_RETRY        = ENV.fetch('AVALARA_RETRY', 2)

  ERRORS_TO_RETRY = [Timeout::Error, Errno::EINVAL, Errno::ECONNRESET,
                     Errno::ECONNREFUSED, EOFError, Net::HTTPBadResponse,
                     Net::HTTPHeaderSyntaxError, Net::ProtocolError].freeze

  def get_tax(request_hash)
    log(__method__, request_hash)

    response = SpreeAvataxCertified::Response::GetTax.new(request('get', request_hash))

    handle_response(response)
  end

  def cancel_tax(request_hash)
    log(__method__, request_hash)

    response = SpreeAvataxCertified::Response::CancelTax.new(request('cancel', request_hash))

    handle_response(response)
  end

  def estimate_tax(coordinates, sale_amount)
    tries ||= AVALARA_RETRY
    if tax_calculation_enabled?
      log(__method__)

      return nil if coordinates.nil?
      sale_amount = 0 if sale_amount.nil?
      coor = coordinates[:latitude].to_s + ',' + coordinates[:longitude].to_s

      uri = URI(service_url + coor + '/get?saleamount=' + sale_amount.to_s)
      http = prepare_http_object(uri)

      res = http.get(uri.request_uri, prepare_http_headers)
      JSON.parse(res.body)
    end
  rescue *ERRORS_TO_RETRY => e
    retry unless (tries -= 1).zero?
    logger.error e, 'Estimate Tax Error'
    'Estimate Tax Error'
  end

  def ping
    logger.info 'Ping Call'
    estimate_tax({ latitude: '40.714623', longitude: '-74.006605' }, 0)
  end

  def validate_address(address)
    tries ||= AVALARA_RETRY
    uri = URI(address_service_url + address.to_query)
    http = prepare_http_object(uri)
    request = http.get(uri.request_uri, 'Authorization' => credential)
    response = SpreeAvataxCertified::Response::AddressValidation.new(request.body)
    handle_response(response)
  rescue *ERRORS_TO_RETRY => e
    retry unless (tries -= 1).zero?
    logger.error(e)
    SpreeAvataxCertified::Response::AddressValidation.new('{}')
  end

  protected

  def handle_response(response)
    result = response.result
    begin
      raise response.result if response.error?

      logger.debug(result, response.description + ' Response')
    rescue => e
      logger.error(e.message, response.description + ' Error')
    end

    response
  end

  def logger
    @logger ||= SpreeAvataxCertified::AvataxLog.new('TaxSvc class', 'Call to tax service')
  end

  private

  def tax_calculation_enabled?
    Spree::Config.avatax_tax_calculation
  end

  def credential
    'Basic ' + Base64.encode64(account_number + ':' + license_key).strip
  end

  def service_url
    Spree::Config.avatax_endpoint + AVATAX_SERVICEPATH_TAX
  end

  def address_service_url
    Spree::Config.avatax_endpoint + AVATAX_SERVICEPATH_ADDRESS + 'validate?'
  end

  def license_key
    Spree::Config.avatax_license_key
  end

  def account_number
    Spree::Config.avatax_account
  end

  def request(uri, request_hash)
    tries ||= AVALARA_RETRY

    full_uri = URI.parse(service_url + uri)
    http = prepare_http_object(full_uri)

    req = Net::HTTP::Post.new(full_uri.path, prepare_http_headers)

    req.body = JSON.generate(request_hash)
    res = http.request(req)
    JSON.parse(res.body)
  rescue *ERRORS_TO_RETRY => e
    retry unless (tries -= 1).zero?
    logger.error e, 'Avalara Request Error'
  end

  def log(method, request_hash = nil)
    return if request_hash.nil?
    logger.debug(request_hash, "#{method} request hash")
  end

  def prepare_http_object(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    http.open_timeout = AVALARA_OPEN_TIMEOUT
    http.read_timeout = AVALARA_READ_TIMEOUT
    http
  end

  def prepare_http_headers
    {
      'Content-Type' => 'application/json',
      'Authorization' => credential
    }
  end
end
