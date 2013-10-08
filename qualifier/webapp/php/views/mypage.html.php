<form action="<?php echo uri_for('/memo') ?>" method="post">
  <input type="hidden" name="sid" value="<?php echo $session["token"] ?>">
  <textarea name="content"></textarea>
  <br>
  <input type="checkbox" name="is_private" value="1"> private
  <input type="submit" value="post">
</form>

<h3>my memos</h3>

<ul>
<?php foreach($memos as $memo) { ?>
<li>
<?php $fragments = preg_split("/\r?\n/", $memo["content"]); ?>
  <a href="<?php echo uri_for('/memo/') ?><?php echo $memo["id"] ?>"><?php echo $fragments[0] ?></a> <?php echo $memo["created_at"] ?>
<?php   if ($memo["is_private"]) { ?>
 [private]
<?php   } ?>
</li>
<?php } ?>
</ul>

