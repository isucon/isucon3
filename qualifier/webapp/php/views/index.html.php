<h3>public memos</h3>
<p id="pager">
  recent <?php echo $page * 100 + 1 ?> - <?php echo $page * 100 + 100 ?> / total <span id="total"><?php echo $total ?></span>
</p>
<ul id="memos">
<?php foreach($memos as $memo) { ?>
<li>
<?php $fragments = preg_split("/\r?\n/", $memo["content"]); ?>
<a href="<?php echo uri_for('/memo/') ?><?php echo $memo["id"] ?>"><?php echo $fragments[0] ?></a> by <?php echo $memo["username"] ?> (<?php echo $memo["created_at"] ?>)
</li>
<?php } ?>
</ul>
















