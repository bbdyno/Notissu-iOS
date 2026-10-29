#!/usr/bin/env ruby
# 노티쓔 앱스토어 커넥트 도구. 키는 ~/.appstoreconnect/private_keys/AuthKey_<ID>.p8(관리자 권한).
#
# 사용법(판은 store/<판>/listing.md 를 읽는다):
#   tooling/asc.rb listing 3.0         listing.md 에서 읽은 칸과 글자 수
#   tooling/asc.rb status 3.0          판 상태, 붙은 빌드, 스크린샷 묶음
#   tooling/asc.rb prepare 3.0         판을 만들고 문구·주소·부제를 넣는다
#   tooling/asc.rb screens 3.0         옛 스크린샷을 모두 빼고 store/<판>/iphone, ipad 그림을 올린다
#   tooling/asc.rb build 3.0 <빌드>    처리가 끝난 빌드를 판에 붙이고 수출 규정 면제를 답한다
#   tooling/asc.rb submit 3.0          심사에 낸다
require 'digest'
require 'base64'
require 'json'
require 'net/http'
require 'openssl'

ISSUER = ENV.fetch('ASC_ISSUER_ID', '69a6de94-516f-47e3-e053-5b8c7c11a4d1')
APP_ID = '1488050194'
KEYS = File.expand_path('~/.appstoreconnect/private_keys')
STORE = File.expand_path('../store', __dir__)
LOCALE = 'ko'
# 폴더 → 앱스토어 기기 슬롯. 6.9형·13형만 올리고 작은 기기는 이것을 줄여 쓴다.
SLOTS = { 'iphone' => 'APP_IPHONE_67', 'ipad' => 'APP_IPAD_PRO_3GEN_129' }.freeze

def key_id
  ENV['ASC_KEY_ID'] ||
    Dir[File.join(KEYS, 'AuthKey_*.p8')]
      .map { |path| File.basename(path, '.p8').delete_prefix('AuthKey_') }
      .reject { |id| id == '46NR2AZ3W8' }.first ||
    abort("관리자 권한 키가 없다: #{KEYS}")
end

def token
  id = key_id
  key = OpenSSL::PKey::EC.new(File.read(File.join(KEYS, "AuthKey_#{id}.p8")))
  encode = ->(text) { Base64.urlsafe_encode64(text, padding: false) }
  now = Time.now.to_i
  input = [
    encode.call({ alg: 'ES256', kid: id, typ: 'JWT' }.to_json),
    encode.call({ iss: ISSUER, iat: now, exp: now + 1200, aud: 'appstoreconnect-v1' }.to_json)
  ].join('.')
  der = key.sign(OpenSSL::Digest.new('SHA256'), input)
  r, s = OpenSSL::ASN1.decode(der).value.map { |part| part.value.to_s(2).rjust(32, "\0") }
  "#{input}.#{encode.call(r + s)}"
end

def call(method, path, body = nil)
  uri = URI("https://api.appstoreconnect.apple.com#{path}")
  request = Net::HTTP.const_get(method.capitalize).new(uri)
  request['Authorization'] = "Bearer #{token}"
  if body
    request['Content-Type'] = 'application/json'
    request.body = body.to_json
  end
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
  parsed = response.body.to_s.empty? ? {} : JSON.parse(response.body.force_encoding('UTF-8'))
  unless response.is_a?(Net::HTTPSuccess)
    details = parsed['errors']&.map { |e| "#{e['title']}: #{e['detail']}" }&.join(' / ')
    abort("#{method} #{path} → #{response.code} #{details}")
  end
  parsed
end

# listing.md 의 "## 제목 (칸)" 절 본문을 칸 이름으로 꺼낸다.
def listing(version_string)
  text = File.read(File.join(STORE, version_string, 'listing.md'), encoding: 'UTF-8')
  fields = {}
  text.split(/^## /).drop(1).each do |section|
    head, body = section.split("\n", 2)
    key = head[/\((\w+)/, 1] or next
    fields[key] = body.strip
  end
  fields['subtitle'] = fields['subtitle']&.lines&.first&.strip
  fields['keywords'] = fields['keywords']&.lines&.first&.strip
  urls = text.scan(/^- .*?\((\w+)\): (\S+)/).to_h
  fields.merge(urls)
end

def version_for(version_string)
  call('get', "/v1/apps/#{APP_ID}/appStoreVersions?filter[versionString]=#{version_string}&filter[platform]=IOS")['data'].first
end

def localization_for(version)
  call('get', "/v1/appStoreVersions/#{version['id']}/appStoreVersionLocalizations")['data']
    .find { |l| l['attributes']['locale'] == LOCALE } || abort("#{LOCALE} 문구가 없다")
end

def editable_app_info
  call('get', "/v1/apps/#{APP_ID}/appInfos")['data']
    .find { |info| info['attributes']['state'] != 'READY_FOR_DISTRIBUTION' } || abort('고칠 수 있는 앱 정보가 없다')
end

def prepare(version_string)
  fields = listing(version_string)
  version = version_for(version_string) || call('post', '/v1/appStoreVersions', {
    data: {
      type: 'appStoreVersions',
      attributes: { versionString: version_string, platform: 'IOS', releaseType: 'AFTER_APPROVAL' },
      relationships: { app: { data: { type: 'apps', id: APP_ID } } }
    }
  })['data']
  puts "판 #{version_string}: #{version['id']}"
  localization = localization_for(version)
  call('patch', "/v1/appStoreVersionLocalizations/#{localization['id']}", {
    data: {
      type: 'appStoreVersionLocalizations', id: localization['id'],
      attributes: {
        whatsNew: fields.fetch('whatsNew'), description: fields.fetch('description'),
        keywords: fields.fetch('keywords'), promotionalText: fields.fetch('promotionalText'),
        supportUrl: fields.fetch('supportUrl'), marketingUrl: fields.fetch('marketingUrl')
      }
    }
  })
  puts '문구·주소를 넣었다'
  info = editable_app_info
  info_localization = call('get', "/v1/appInfos/#{info['id']}/appInfoLocalizations")['data']
                      .find { |l| l['attributes']['locale'] == LOCALE }
  call('patch', "/v1/appInfoLocalizations/#{info_localization['id']}", {
    data: {
      type: 'appInfoLocalizations', id: info_localization['id'],
      attributes: { subtitle: fields.fetch('subtitle'), privacyPolicyUrl: fields.fetch('privacyPolicyUrl') }
    }
  })
  puts '부제·처리방침 주소를 넣었다'
end

def upload(set_id, path)
  bytes = File.binread(path)
  reserved = call('post', '/v1/appScreenshots', {
    data: {
      type: 'appScreenshots',
      attributes: { fileName: File.basename(path), fileSize: bytes.bytesize },
      relationships: { appScreenshotSet: { data: { type: 'appScreenshotSets', id: set_id } } }
    }
  })['data']
  reserved['attributes']['uploadOperations'].each do |operation|
    uri = URI(operation['url'])
    request = Net::HTTP.const_get(operation['method'].capitalize).new(uri)
    operation['requestHeaders'].each { |header| request[header['name']] = header['value'] }
    request.body = bytes.byteslice(operation['offset'], operation['length'])
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
    abort("올리기 실패 #{response.code}") unless response.is_a?(Net::HTTPSuccess)
  end
  call('patch', "/v1/appScreenshots/#{reserved['id']}", {
    data: {
      type: 'appScreenshots', id: reserved['id'],
      attributes: { uploaded: true, sourceFileChecksum: Digest::MD5.hexdigest(bytes) }
    }
  })
end

def screens(version_string)
  localization = localization_for(version_for(version_string) || abort('판이 없다'))
  sets = call('get', "/v1/appStoreVersionLocalizations/#{localization['id']}/appScreenshotSets?limit=50")['data']
  sets.each do |set|
    call('delete', "/v1/appScreenshotSets/#{set['id']}")
    puts "옛 묶음을 뺐다: #{set['attributes']['screenshotDisplayType']}"
  end
  SLOTS.each do |folder, slot|
    files = Dir[File.join(STORE, version_string, folder, 'raw-*.png')].sort
    next if files.empty?
    set = call('post', '/v1/appScreenshotSets', {
      data: {
        type: 'appScreenshotSets', attributes: { screenshotDisplayType: slot },
        relationships: { appStoreVersionLocalization: { data: { type: 'appStoreVersionLocalizations', id: localization['id'] } } }
      }
    })['data']
    files.each { |path| upload(set['id'], path) }
    puts "#{slot}: #{files.size}장"
  end
end

def attach_build(version_string, build_number)
  version = version_for(version_string) || abort('판이 없다')
  build = call('get', "/v1/builds?filter[app]=#{APP_ID}&filter[version]=#{build_number}")['data'].first ||
          abort("빌드 #{build_number}가 아직 없다")
  state = build['attributes']['processingState']
  abort("빌드 처리 중: #{state}") unless state == 'VALID'
  if build['attributes']['usesNonExemptEncryption'].nil?
    call('patch', "/v1/builds/#{build['id']}", {
      data: { type: 'builds', id: build['id'], attributes: { usesNonExemptEncryption: false } }
    })
  end
  call('patch', "/v1/appStoreVersions/#{version['id']}/relationships/build", { data: { type: 'builds', id: build['id'] } })
  puts "빌드 #{build_number}를 붙였다"
end

def submit(version_string)
  version = version_for(version_string) || abort('판이 없다')
  # 앞서 막힌 제출이 열려 있으면 그것을 다시 쓴다. 연령 등급 설문 같은 빈칸이 있으면 409로 막힌다.
  submission = call('get', "/v1/reviewSubmissions?filter[app]=#{APP_ID}&filter[state]=READY_FOR_REVIEW")['data'].first ||
               call('post', '/v1/reviewSubmissions', {
                 data: {
                   type: 'reviewSubmissions', attributes: { platform: 'IOS' },
                   relationships: { app: { data: { type: 'apps', id: APP_ID } } }
                 }
               })['data']
  call('post', '/v1/reviewSubmissionItems', {
    data: {
      type: 'reviewSubmissionItems',
      relationships: {
        reviewSubmission: { data: { type: 'reviewSubmissions', id: submission['id'] } },
        appStoreVersion: { data: { type: 'appStoreVersions', id: version['id'] } }
      }
    }
  })
  call('patch', "/v1/reviewSubmissions/#{submission['id']}", {
    data: { type: 'reviewSubmissions', id: submission['id'], attributes: { submitted: true } }
  })
  puts "심사에 냈다: #{submission['id']}"
end

def status(version_string)
  version = version_for(version_string)
  abort("판 #{version_string}이 아직 없다") unless version
  build = call('get', "/v1/appStoreVersions/#{version['id']}/build")['data']
  puts "판 #{version_string}: #{version['attributes']['appStoreState']}, 빌드 #{build ? build['attributes']['version'] : '없음'}"
  localization = localization_for(version)
  call('get', "/v1/appStoreVersionLocalizations/#{localization['id']}/appScreenshotSets?limit=50")['data'].each do |set|
    shots = call('get', "/v1/appScreenshotSets/#{set['id']}/appScreenshots?limit=50")['data']
    states = shots.map { |shot| shot['attributes'].dig('assetDeliveryState', 'state') }.group_by(&:itself).transform_values(&:size)
    puts "  #{set['attributes']['screenshotDisplayType']}: #{shots.size}장 #{states}"
  end
end

command, version_string, extra = ARGV
abort(File.read(__FILE__)[/^# 사용법.*?(?=^require)/m]) unless command && version_string
case command
when 'status' then status(version_string)
when 'listing' then listing(version_string).each { |k, v| puts "#{k}: #{v.length} | #{v[0, 50].gsub("\n", ' ')}" }
when 'prepare' then prepare(version_string)
when 'screens' then screens(version_string)
when 'build' then attach_build(version_string, extra || abort('빌드 번호를 준다'))
when 'submit' then submit(version_string)
else abort("모르는 명령: #{command}")
end
