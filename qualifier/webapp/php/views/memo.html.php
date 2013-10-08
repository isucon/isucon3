<p id="author">
<?php if ($memo['is_private']) { ?>
Private
<?php } else { ?>
Public
<?php } ?>
Memo by <?php echo $memo['username'] ?> (<?php echo $memo['created_at'] ?>)
</p>

<hr>
<?php if ($older) { ?>
<a id="older" href="<?php echo uri_for('/memo/') ?><?php echo $older['id'] ?>">&lt; older memo</a>
<?php } ?>
|
<?php if ($newer) { ?>
<a id="newer" href="<?php echo uri_for('/memo/') ?><?php echo $newer['id'] ?>">newer memo &gt;</a>
<?php } ?>

<hr>
<div id="content_html">
<?php echo $memo['content_html'] ?>
</div>


