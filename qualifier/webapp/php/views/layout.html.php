<!DOCTYPE html>
<html>
<head>
<meta http-equiv="Content-Type" content="text/html" charset="utf-8">
<title>Isucon3</title>
<link rel="stylesheet" href="<?php echo uri_for('/css/bootstrap.min.css') ?>">
<style>
body {
  padding-top: 60px;
}
</style>
<link rel="stylesheet" href="<?php echo uri_for('/css/bootstrap-responsive.min.css') ?>">
<link rel="stylesheet" href="/">
</head>
<body>
<div class="navbar navbar-fixed-top">
<div class="navbar-inner">
<div class="container">
<a class="btn btn-navbar" data-toggle="collapse" data-target=".nav-collapse">
<span class="icon-bar"></span>
<span class="icon-bar"></span>
<span class="icon-bar"></span>
</a>
<a class="brand" href="<?php echo uri_for('/') ?>">Isucon3</a>
<div class="nav-collapse">
<ul class="nav">
<li><a href="<?php echo uri_for('/') ?>">Home</a></li>
<?php if (isset($user) && $user) { ?>
<li><a href="<?php echo uri_for('/mypage') ?>">MyPage</a></li>
<li>
  <form action="<?php echo uri_for('/signout') ?>" method="post">
    <input type="hidden" name="sid" value="<?php echo $session["token"] ?>">
    <input type="submit" value="SignOut">
  </form>
</li>
<?php } else { ?>
<li><a href="<?php echo uri_for('/signin') ?>">SignIn</a></li>
<?php } ?>
</ul>
</div> <!--/.nav-collapse -->
</div>
</div>
</div>

<div class="container">
<h2>Hello <?php if (isset($user) && $user) { echo $user["username"]; } ?>!</h2>

<?php echo $content ?>

</div> <!-- /container -->

<script type="text/javascript" src="<?php echo uri_for('/js/jquery.min.js') ?>"></script>
<script type="text/javascript" src="<?php echo uri_for('/js/bootstrap.min.js') ?>"></script>
</body>
</html>











