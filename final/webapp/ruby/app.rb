require 'sinatra/base'
require 'sinatra/json'
require 'json'
require 'mysql2-cs-bind'
require 'digest/sha2'
require 'tempfile'
require 'fileutils'
require 'uuid'

class Isucon3Final < Sinatra::Base
  $stdout.sync = true
  TIMEOUT  = 30
  INTERVAL =  2
  $UUID    = UUID.new

  ICON_S  =  32
  ICON_M  =  64
  ICON_L  = 128
  IMAGE_S = 128
  IMAGE_M = 256
  IMAGE_L = nil

  helpers do
    def load_config
      return $config if $config
      $config = JSON.parse(IO.read(File.dirname(__FILE__) + "/../config/#{ ENV['ISUCON_ENV'] || 'local' }.json"))
    end

    def connection
      config = load_config['database']
      return $mysql if $mysql
      $mysql = Mysql2::Client.new(
        :host      => config['host'],
        :port      => config['port'],
        :username  => config['username'],
        :password  => config['password'],
        :database  => config['dbname'],
        :reconnect => true,
      )
    end

    def convert(orig, ext, w, h)
      data = nil

      Tempfile.open('isucontemp') do |tmp|
        newfile = "#{tmp.path}.#{ext}"
        `convert -geometry #{w}x#{h} #{orig} #{newfile}`
        File.open(newfile, 'r+b') do |new|
          data = new.read
        end
        File.unlink(newfile)
      end

      data
    end

    def crop_square(orig, ext)
      identity = `identify #{orig}`
      (w, h)   = identity.split[2].split('x').map(&:to_i)

      if w > h
        pixels = h
        crop_x = ((w - pixels) / 2).floor
        crop_y = 0
      elsif w < h
        pixels = w
        crop_x = 0
        crop_y = ((h - pixels) / 2).floor
      else
        pixels = w
        crop_x = 0
        crop_y = 0
      end

      tmp     = Tempfile.open("isucon")
      newfile = "#{tmp.path}.#{ext}"
      `convert -crop #{pixels}x#{pixels}+#{crop_x}+#{crop_y} #{orig} #{newfile}`
      tmp.close
      tmp.unlink

      newfile
    end

    def get_user
      mysql   = connection

      api_key = env["HTTP_X_API_KEY"] || request.cookies["api_key"]
      if api_key
        user = mysql.xquery('SELECT * FROM users WHERE api_key = ?', api_key).first
      end

      user
    end

    def require_user(user)
      unless user
        halt 400, "400 Bad Request"
      end
    end

    def uri_for(path)
      scheme = request.scheme
      if (scheme == 'http' && request.port == 80 ||
          scheme == 'https' && request.port == 443)
        port = ""
      else
        port = ":#{request.port}"
      end
      base = "#{scheme}://#{request.host}#{port}#{request.script_name}"
      "#{base}#{path}"
    end

    def params_with_multi_value(key)
      value = Rack::Utils.parse_query(@env['rack.request.form_vars'])[key]
      value.is_a?(Array) ? value : [value]
    end
  end

  get '/' do
    File.read(File.join('public', 'index.html'))
  end

  post '/signup' do
    mysql = connection

    name = params[:name]
    unless name.match(/\A[0-9a-zA-Z_]{2,16}\z/)
      halt 400, "400 Bad Request"
    end

    api_key = Digest::SHA256.hexdigest($UUID.generate)
    mysql.xquery(
      'INSERT INTO users (name, api_key, icon) VALUES (?, ?, ?)',
      name, api_key, 'default'
    )
    id   = mysql.last_id
    user = mysql.xquery('SELECT * FROM users WHERE id = ?', id).first

    json({
      :id      => user["id"].to_i,
      :name    => user["name"],
      :icon    => uri_for("/icon/#{ user["icon"] }"),
      :api_key => user["api_key"]
    })
  end

  get '/me' do
    user = get_user
    require_user(user)

    json({
      :id      => user["id"].to_i,
      :name    => user["name"],
      :icon    => uri_for("/icon/#{ user["icon"] }")
    })
  end

  get '/icon/:icon' do
    icon = params[:icon]
    size = params[:size] || 's'
    dir  = load_config['data_dir']

    icon_path = "#{dir}/icon/#{icon}.png"
    unless File.exist?(icon_path)
      halt 404
    end

    w = size == 's' ? ICON_S
      : size == 'm' ? ICON_M
      : size == 'l' ? ICON_L
      :               ICON_S
    h = w

    content_type 'image/png'
    convert(icon_path, 'png', w, h)
  end

  post '/icon' do
    mysql = connection
    user  = get_user
    require_user(user)

    upload = params[:image]
    unless upload
      halt 400, "400 Bad Request"
    end
    unless upload[:type].match(/^image\/(jpe?g|png)$/)
      halt 400, "400 Bad Request"
    end

    file = crop_square(upload[:tempfile].path, 'png')
    icon = Digest::SHA256.hexdigest($UUID.generate)
    dir  = load_config['data_dir']
    FileUtils.move(file, "#{dir}/icon/#{icon}.png") or halt 500

    mysql.xquery(
      'UPDATE users SET icon = ? WHERE id = ?',
      icon, user["id"]
    )
    json({
      :icon => uri_for("/icon/#{icon}")
    })
  end

  post '/entry' do
    mysql = connection
    user  = get_user
    require_user(user)

    upload = params[:image]
    unless upload
      halt 400, "400 Bad Request"
    end
    unless upload[:type].match(/^image\/jpe?g$/)
      halt 400, "400 Bad Request"
    end

    image_id = Digest::SHA256.hexdigest($UUID.generate)
    dir      = load_config['data_dir']
    FileUtils.move(upload[:tempfile].path, "#{dir}/image/#{image_id}.jpg") or halt 500

    publish_level = params[:publish_level]
    mysql.xquery(
      'INSERT INTO entries (user, image, publish_level, created_at) VALUES (?, ?, ?, NOW())',
      user["id"], image_id, publish_level
    )
    id    = mysql.last_id
    entry = mysql.xquery('SELECT * FROM entries WHERE id = ?', id).first

    json({
      :id            => entry["id"].to_i,
      :image         => uri_for("/image/#{entry["image"]}"),
      :publish_level => publish_level.to_i,
      :user => {
        :id   => user["id"].to_i,
        :name => user["name"],
        :icon => uri_for("/icon/#{user["icon"]}")
      }
    })
  end

  post '/entry/:id' do
    mysql = connection
    user  = get_user
    require_user(user)

    id  = params[:id].to_i

    entry = mysql.xquery('SELECT * FROM entries WHERE id = ?', id).first
    unless entry
      halt 404
    end
    unless entry["user"] == user["id"] && params["__method"] == 'DELETE'
      halt 400, "400 Bad Request"
    end

    mysql.xquery('DELETE FROM entries WHERE id = ?', id)

    json({
      :ok => true
    })
  end

  get '/image/:image' do
    mysql = connection
    user  = get_user

    image = params[:image]
    size  = params[:size] || 'l'
    dir   = load_config['data_dir']

    entry = mysql.xquery('SELECT * FROM entries WHERE image = ?', image).first
    unless entry
      halt 404
    end
    if entry["publish_level"] == 0
      if user && entry["user"] == user["id"]
        # publish_level==0 はentryの所有者しか見えない
        # ok
      else
        halt 404
      end
    elsif entry["publish_level"] == 1
      # publish_level==1 はentryの所有者かfollowerしか見えない
      if user && entry["user"] == user["id"]
        # ok
      elsif user
        follow = mysql.xquery(
          'SELECT * FROM follow_map WHERE user = ? AND target = ?',
          user["id"], entry["user"]
        ).first
        halt 404 unless follow
      else
        halt 404
      end
    end

    w = size == 's' ? IMAGE_S
      : size == 'm' ? IMAGE_M
      : size == 'l' ? IMAGE_L
      :               IMAGE_L
    h = w

    if w
      file = crop_square("#{dir}/image/#{image}.jpg", 'jpg')
      data = convert(file, 'jpg', w, h)
      File.unlink(file)
    else
      file = File.open("#{dir}/image/#{image}.jpg", 'r+b')
      data = file.read
      file.close
    end

    content_type 'image/jpeg'
    data
  end

  def get_following
    mysql = connection
    user  = get_user
    require_user(user)

    following = mysql.xquery(
      'SELECT users.* FROM follow_map JOIN users ON (follow_map.target = users.id) WHERE follow_map.user = ? ORDER BY follow_map.created_at DESC',
      user["id"]
    )

    headers "Cache-Control" => "no-cache"
    json({
      :users => following.map do |u|
        {
          :id   => u["id"].to_i,
          :name => u["name"],
          :icon => uri_for("/icon/#{u["icon"]}")
        }
      end
    })
  end

  get '/follow' do
    get_following
  end

  post '/follow' do
    mysql = connection
    user  = get_user
    require_user(user)

    params_with_multi_value('target').each do |target|
      next if target == user["id"]

      mysql.xquery(
        'INSERT IGNORE INTO follow_map (user, target, created_at) VALUE (?, ?, NOW())',
        user["id"], target
      )
    end

    get_following
  end

  post '/unfollow' do
    mysql = connection
    user  = get_user
    require_user(user)

    params_with_multi_value('target').each do |target|
      next if target == user["id"]

      mysql.xquery(
        'DELETE FROM follow_map WHERE user = ? AND target = ?',
        user["id"], target
      )
    end

    get_following
  end

  get '/timeline' do
    mysql = connection
    user  = get_user
    require_user(user)

    latest_entry = params[:latest_entry]
    if latest_entry
        sql = 'SELECT * FROM (SELECT * FROM entries WHERE (user=? OR publish_level=2 OR (publish_level=1 AND user IN (SELECT target FROM follow_map WHERE user=?))) AND id > ? ORDER BY id LIMIT 30) AS e ORDER BY e.id DESC'
        params = [user["id"], user["id"], latest_entry]
    else
        sql = 'SELECT * FROM entries WHERE (user=? OR publish_level=2 OR (publish_level=1 AND user IN (SELECT target FROM follow_map WHERE user=?))) ORDER BY id DESC LIMIT 30'
        params = [user["id"], user["id"]]
    end

    start        = Time.now.to_i
    entries      = []
    while Time.now.to_i - start < TIMEOUT
      _entries = mysql.xquery(sql, *params)

      if _entries.size == 0
        sleep INTERVAL
        next
      else
        entries      = _entries
        latest_entry = entries.first["id"]
        break
      end
    end

    headers "Cache-Control" => "no-cache"
    json({
      :latest_entry => latest_entry.to_i,
      :entries => entries.map do |entry|
        user = mysql.xquery('SELECT * FROM users WHERE id = ?', entry["user"]).first
        {
          :id            => entry["id"].to_i,
          :image         => uri_for("/image/#{entry["image"]}"),
          :publish_level => entry["publish_level"].to_i,
          :user => {
            :id   => user["id"].to_i,
            :name => user["name"],
            :icon => uri_for("/icon/#{user["icon"]}")
          }
        }
      end
    })
  end

  run! if app_file == $0
end
