<?php
require_once 'lib/limonade.php';

function convert($orig, $ext, $w, $h) {
    $filename = tempnam('/tmp', 'ISUCON');
    $fh       = fopen($filename, 'w');
    $newfile  = "${filename}.${ext}";
    exec("convert -geometry ${w}x${h} ${orig} ${newfile}");
    if (!($data = file_get_contents($newfile))) {
        die();
    }

    unlink($filename);
    unlink($newfile);

    return $data;
}

function crop_square($orig, $ext) {
    exec("identify ${orig}", $output);
    $identity    = preg_split('/ +/', $output[0]);
    list($w, $h) = explode('x', $identity[2]);
    if ($w > $h) {
        $pixels = $h;
        $crop_x = floor(($w - $pixels) / 2);
        $crop_y = 0;
    } elseif ($w < $h) {
        $pixels = $w;
        $crop_x = 0;
        $crop_y = floor(($h - $pixels) / 2);
    } else {
        $pixels = $w;
        $crop_x = 0;
        $crop_y = 0;
    }

    $filename = tempnam('/tmp', 'ISUCON');
    exec("convert -crop ${pixels}x${pixels}+${crop_x}+${crop_y} ${orig} ${filename}.${ext}");

    unlink($filename);

    return "${filename}.${ext}";
}

function uri_for($path)
{
    $scheme = isset($_SERVER['HTTPS']) ? 'https' : 'http';
    $host   = isset($_SERVER['HTTP_X_FORWARDED_HOST']) ? $_SERVER['HTTP_X_FORWARDED_HOST']
                                                       : $_SERVER['HTTP_HOST'];
    $base   = $scheme . '://' . $host;

    return $base . $path;
}

function get($key)
{
    return set($key);
}

function get_http_parameters($method) {
    switch ($method) {
        case 'GET':  $str = $_SERVER['QUERY_STRING']; break;
        case 'POST': $str = file_get_contents('php://input'); break;
        default: $str = '';
    }

    $params = array();
    foreach (explode('&', $str) as $param) {
        list($key, $value) = explode('=', $param);
        $params[urldecode($key)][] = urldecode($value);
    }

    return $params;
}

function configure()
{
    error_reporting(E_ALL ^ E_NOTICE);

    define('TIMEOUT', 30);
    define('INTERVAL', 2);

    define('ICON_S', 32);
    define('ICON_M', 64);
    define('ICON_L', 128);
    define('IMAGE_S', 128);
    define('IMAGE_M', 256);
    define('IMAGE_L', null);
    option('session', null);
    option('views_dir', realpath(__DIR__ . '/public'));

    $env = getenv('ISUCON_ENV');
    if (!$env) {
        $env = 'local';
    }
    $file   = realpath(__DIR__ . '/../config/' . $env . '.json');
    $fh     = fopen($file, 'r');
    $config = json_decode(fread($fh, filesize($file)), true);
    option('data_dir', $config['data_dir']);
    fclose($fh);

    $db = null;
    try {
        $db = new PDO(
            'mysql:host=' . $config['database']['host'] . ';dbname=' . $config['database']['dbname'],
            $config['database']['username'],
            $config['database']['password'],
            array(
                PDO::ATTR_PERSISTENT         => true,
                PDO::MYSQL_ATTR_INIT_COMMAND => 'SET CHARACTER SET `utf8`',
            )
        );
    } catch (PDOException $e) {
        halt("Connection failed: ${e}");
    }
    $db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    option('db_conn', $db);
}

function before($route)
{
    $path = $_SERVER['QUERY_STRING'];

    if (
        in_array($path, array('/me', '/icon', '/follow', '/unfollow'))
        || preg_match('/^\/(entry|image|timeline)(.*)$/', $path)
    ) {
        filter_get_user($route);
    }

    if (
        in_array($path, array('/icon', '/follow', '/unfollow'))
        || preg_match('/^\/(entry|timeline)(.*)$/', $path)
    ) {
        filter_require_user($route);
    }
}

function filter_get_user($route)
{
    $db = option('db_conn');

    foreach (getallheaders() as $name => $value) {
        if (strtolower($name) === "x-api-key") {
            $api_key = $value;
        }
    }
    if (!$api_key) {
        $api_key = $_COOKIE['api_key'];
    }

    $stmt = $db->prepare('SELECT * FROM users WHERE api_key = :api_key');
    $stmt->bindValue(':api_key', $api_key);
    $stmt->execute();
    $user = $stmt->fetch(PDO::FETCH_ASSOC);

    set('user', $user);
}

function filter_require_user($route)
{
    if (!get('user')) {
        return halt(400);
    }
}

dispatch_get('/', function()
{
    return render('index.html');
});

dispatch_post('/signup', function()
{
    $db = option('db_conn');

    $name = $_POST['name'];
    if (!preg_match('/^[0-9a-zA-Z_]{2,16}$/', $name)) {
        return halt(400);
    }
    $api_key = hash('sha256', uuid_create(UUID_TYPE_TIME), false);

    $stmt = $db->prepare('INSERT INTO users (name, api_key, icon) VALUES (:name, :api_key, :icon)');
    $stmt->bindValue(':name', $name);
    $stmt->bindValue(':api_key', $api_key);
    $stmt->bindValue(':icon', 'default');
    $stmt->execute();

    $id = $db->lastInsertId();

    $stmt = $db->prepare('SELECT * FROM users WHERE id = :id');
    $stmt->bindValue(':id', $id);
    $stmt->execute();
    $user = $stmt->fetch(PDO::FETCH_ASSOC);

    return json(array(
        'id'      => $user['id'],
        'name'    => $user['name'],
        'icon'    => uri_for('/icon/' . $user['icon']),
        'api_key' => $user['api_key'],
    ));
});


dispatch_get('/me', function()
{
    $user = get('user');

    return json(array(
        'id'   => $user['id'],
        'name' => $user['name'],
        'icon' => uri_for('/icon/' . $user['icon']),
    ));
});

dispatch_get('/icon/:icon', function()
{
    $icon = params('icon');
    $size = $_GET['size'] ? $_GET['size'] : 's';
    $dir  = option('data_dir');
    if (!file_exists("${dir}/icon/${icon}.png")) {
        return halt(404);
    }

    switch ($size){
        case 's': $w = constant('ICON_S'); break;
        case 'm': $w = constant('ICON_M'); break;
        case 'l': $w = constant('ICON_L'); break;
        default:  $w = constant('ICON_S');
    }
    $h = $w;

    $data = convert("${dir}/icon/${icon}.png", 'png', $w, $h);

    send_header('Content-Type: image/png');
    return $data;
});

dispatch_post('/icon', function()
{
    $db   = option('db_conn');
    $user = get('user');

    if (!is_uploaded_file($_FILES['image']['tmp_name'])) {
        return halt(400);
    }
    if (!preg_match('/^image\/(jpe?g|png)$/', $_FILES['image']['type'])) {
        return halt(400);
    }

    $file = crop_square($_FILES['image']['tmp_name'], 'png');
    $icon = hash('sha256', uuid_create(UUID_TYPE_TIME), false);
    $dir  = option('data_dir');
    if (!rename($file, "${dir}/icon/${icon}.png")) {
        return halt(500);
    };

    $stmt = $db->prepare('UPDATE users SET icon = :icon WHERE id = :id');
    $stmt->bindValue(':icon', $icon);
    $stmt->bindValue(':id', $user['id']);
    $stmt->execute();

    return json(array(
        'icon' => uri_for("/icon/${icon}"),
    ));
});

dispatch_post('/entry', function()
{
    $db   = option('db_conn');
    $user = get('user');

    if (!is_uploaded_file($_FILES['image']['tmp_name'])) {
        return halt(400);
    }
    if (!preg_match('/^image\/jpe?g$/', $_FILES['image']['type'])) {
        return halt(400);
    }

    $image_id = hash('sha256', uuid_create(UUID_TYPE_TIME), false);
    $dir      = option('data_dir');
    if (!move_uploaded_file($_FILES['image']['tmp_name'], "${dir}/image/${image_id}.jpg")) {
        return halt(500);
    };

    $publish_level = $_POST['publish_level'];

    $stmt = $db->prepare('INSERT INTO entries (user, image, publish_level, created_at) VALUES (:user, :image, :publish_level, now())');
    $stmt->bindValue(':user', $user['id']);
    $stmt->bindValue(':image', $image_id);
    $stmt->bindValue(':publish_level', $publish_level);
    $stmt->execute();

    $id = $db->lastInsertId();

    $stmt = $db->prepare('SELECT * FROM entries WHERE id = :id');
    $stmt->bindValue(':id', $id);
    $stmt->execute();
    $entry = $stmt->fetch(PDO::FETCH_ASSOC);

    return json(array(
        'id'            => $entry['id'],
        'image'         => uri_for('/image/' . $entry['image']),
        'publish_level' => $entry['publish_level'],
        'user' => array(
            'id'   => $user['id'],
            'name' => $user['name'],
            'icon' => uri_for('/icon/' . $user['icon']),
        ),
    ));
});

dispatch_post('/entry/:id', function()
{
    $db   = option('db_conn');
    $user = get('user');

    $id  = params('id');
    $dir = option('data_dir');

    $stmt = $db->prepare('SELECT * FROM entries WHERE id = :id');
    $stmt->bindValue(':id', $id);
    $stmt->execute();
    $entry = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$entry) {
        return halt(404);
    }
    if ($entry['user'] != $user['id'] || $_POST['__method'] != 'DELETE') {
        return halt(400);
    }

    $stmt = $db->prepare('DELETE FROM entries WHERE id = :id');
    $stmt->bindValue(':id', $id);
    $stmt->execute();

    return json(array(
        'ok' => true,
    ));
});

dispatch_get('/image/:image', function()
{
    $db   = option('db_conn');
    $user = get('user');

    $image = params('image');
    $size  = $_GET['size'] ? $_GET['size'] : 'l';
    $dir   = option('data_dir');

    $stmt = $db->prepare('SELECT * FROM entries WHERE image = :image');
    $stmt->bindValue(':image', $image);
    $stmt->execute();
    $entry = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$entry) {
        return halt(404);
    }
    if ($entry['publish_level'] == 0) {
        if ($user && $entry['user'] == $user['id']) {
            // ok
        } else {
            return halt(404);
        }
    }
    elseif ($entry['publish_level'] == 1) {
        if ($entry['user'] == $user['id']) {
            // ok
        } else {
            $stmt = $db->prepare('SELECT * FROM follow_map WHERE user = :user AND target = :target');
            $stmt->bindValue(':user', $user['id']);
            $stmt->bindValue(':target', $entry['user']);
            $stmt->execute();
            $follow = $stmt->fetch(PDO::FETCH_ASSOC);
            if (!$follow) {
                return halt(404);
            }
        }
    }

    switch ($size){
        case 's': $w = constant('IMAGE_S'); break;
        case 'm': $w = constant('IMAGE_M'); break;
        case 'l': $w = constant('IMAGE_L'); break;
        default:  $w = constant('IMAGE_L');
    }
    $h = $w;

    if ($w) {
        $file = crop_square("${dir}/image/${image}.jpg", 'jpg');
        $data = convert($file, 'jpg', $w, $h);
        unlink($file);
    } else {
        if (!($data = file_get_contents("${dir}/image/${image}.jpg"))) {
            return halt(500);
        }
    }

    send_header('Content-Type: image/jpeg');
    return $data;
});

function get_following() {
    $db   = option('db_conn');
    $user = get('user');

    $stmt = $db->prepare('SELECT users.* FROM follow_map JOIN users ON (follow_map.target = users.id) WHERE follow_map.user = :user ORDER BY follow_map.created_at DESC');
    $stmt->bindValue(':user', $user['id']);
    $stmt->execute();
    $followings = $stmt->fetchAll(PDO::FETCH_ASSOC);

    $users = array();
    foreach ($followings as $following) {
        $users[] = array(
            'id'   => $following['id'],
            'name' => $following['name'],
            'icon' => uri_for('/icon/' . $following['icon']),
        );
    }

    send_header('Cache-Control: no-cache');
    echo json(array(
        users => $users,
    ));
}

dispatch_get('/follow', function()
{
    get_following();
});

dispatch_post('/follow', function()
{
    $db   = option('db_conn');
    $user = get('user');

    $params = get_http_parameters('POST');
    foreach ($params['target'] as $target) {
        if ($target == $user['id']) {
            continue;
        };

        $stmt = $db->prepare('INSERT IGNORE INTO follow_map (user, target, created_at) VALUES (:user, :target, now())');
        $stmt->bindValue(':user', $user['id']);
        $stmt->bindValue(':target', $target);
        $stmt->execute();
    }

    get_following();
});

dispatch_post('/unfollow', function()
{
    $db   = option('db_conn');
    $user = get('user');

    $params = get_http_parameters('POST');
    foreach ($params['target'] as $target) {
        if ($target == $user['id']) {
            continue;
        };

        $stmt = $db->prepare('DELETE FROM follow_map WHERE user = :user AND target = :target');
        $stmt->bindValue(':user', $user['id']);
        $stmt->bindValue(':target', $target);
        $stmt->execute();
    }

    get_following();
});

dispatch_get('/timeline', function()
{
    $db   = option('db_conn');
    $user = get('user');

    $latest_entry = $_GET['latest_entry'];
    if ($latest_entry) {
        $stmt = $db->prepare('SELECT * FROM (SELECT * FROM entries WHERE (user = :user OR publish_level = 2 OR (publish_level = 1 AND user IN (SELECT target FROM follow_map WHERE user = :user))) AND id > :id ORDER BY id LIMIT 30) AS e ORDER BY e.id DESC');
        $stmt->bindValue(':user', $user['id']);
        $stmt->bindValue(':id', $latest_entry);
    }
    else {
        $stmt = $db->prepare('SELECT * FROM entries WHERE (user = :user OR publish_level = 2 OR (publish_level = 1 AND user IN (SELECT target FROM follow_map WHERE user = :user))) ORDER BY id DESC LIMIT 30');
        $stmt->bindValue(':user', $user['id']);
    }

    $start = time();
    while (time() - $start < constant('TIMEOUT')) {
        $stmt->execute();
        $entries = $stmt->fetchAll(PDO::FETCH_ASSOC);

        if (count($entries) == 0) {
            sleep(constant('INTERVAL'));
            continue;
        }
        else {
            $latest_entry = $entries[0]['id'];
            break;
        }
    }

    $entries_arranged = array();
    foreach ($entries as $entry) {
        $stmt = $db->prepare('SELECT * FROM users WHERE id = :id');
        $stmt->bindValue(':id', $entry['user']);
        $stmt->execute();
        $user = $stmt->fetch(PDO::FETCH_ASSOC);

        $entries_arranged[] = array(
            'id'            => $entry['id'],
            'image'         => uri_for('/image/' . $entry['image']),
            'publish_level' => $entry['publish_level'],
            'user' => array(
                'id'   => $user['id'],
                'name' => $user['name'],
                'icon' => uri_for('/icon/' . $user['icon']),
            ),
        );
    }

    return json(array(
        'latest_entry' => $latest_entry,
        'entries'      => $entries_arranged,
    ));
});

run();