DROP TABLE IF EXISTS `users`;
CREATE TABLE `users` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL,
  `api_key` varchar(255) NOT NULL,
  `icon` varchar(255) NOT NULL default 'default',
  PRIMARY KEY (`id`),
  UNIQUE KEY `api_key_idx` (`api_key`)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;

DROP TABLE IF EXISTS `entries`;
CREATE TABLE `entries` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `user` int(11) NOT NULL,
  `image` varchar(255) NOT NULL,
  `publish_level` int(11) NOT NULL default 0,
  `created_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `entries_user` (`user`)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;

DROP TABLE IF EXISTS `follow_map`;
CREATE TABLE `follow_map` (
  `user` int(11) NOT NULL,
  `target` int(11) NOT NULL,
  `created_at` datetime NOT NULL,
  PRIMARY KEY (`user`, `target`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
