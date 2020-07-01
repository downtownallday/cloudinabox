<?php

#
# Edit a Nextcloud config.php file
#
# Specify the path to config.php as the first argument.
#
# Subsequent arguments specify the name and value pairs of elements to
#  change or add. Each element of the pair are separate
#  arguments. Arrays should be specified as "array(...)".
#
# Names may be preceeded with '+' to indicate that the value should be
# added, but not modify an existing value if it already exists.
#
# For example, to set dbhost to 'localhost' and trusted_domains to an
# array of values:
#
#   sudo -u www-data php editconfig.php /usr/local/nextcloud/config/config.php dbhost localhost trusted_domains "array(0=>'localhost',1=>'127.0.0.1')"
#
# The original file is MODIFIED in-place!!!
#

require($argv[1]);

$dry_run = false;


function print_array($v, $level, $fp) {
  fwrite($fp, "array (\n");

  if ((array) $v !== $v) {
     foreach($v as $kv) {
         fwrite($fp, $kv . ",");
     }
  }
  else {
     foreach($v as $key => $kv) {
       fwrite($fp,str_repeat('    ', $level));
       if (is_string($key)) {
          fwrite($fp,"'" . $key . "' => ");
       }
       else {
          fwrite($fp,$key . " => ");
       }
       
       if (is_array($kv)) {
           print_array($kv, $level+1, $fp);
       }
       else if (is_string($kv)) {
           fwrite($fp,"'" . $kv . "',\n");
       }
       else if (is_bool($kv)) {
           fwrite($fp, ($kv ? 'true' : 'false') . ",\n");
       }
       else {
           fwrite($fp,$kv . ",\n");
       }
     }
  }
  fwrite($fp,str_repeat('    ', $level-1));
  fwrite($fp,")");
  if ($level>1) fwrite($fp,",\n");
}


for($i=2; $i<count($argv); $i+=2) {
   $overwrite = true;
   
   $name=$argv[$i];
   if (substr($name,0,1) == "+") {
       $overwrite = false;
       $name=substr($name,1);
   }

   $value=$argv[$i+1];
   if(substr($value,0,5) == "array") {
       $value = eval('return ' . $value . ';');
   }
   else if (is_numeric($value)) {
       if (strstr($value, ".") === FALSE) $value = intval($value);
       else $value = floatval($value);
   }
   else if ($value == "true") {
       $value = true;
   }
   else if ($value == "false") {
       $value = false;
   }

   if ($overwrite || ! array_key_exists($name, $CONFIG)) {
       $CONFIG[$name] = $value;
   }
}


if ($dry_run) {
   $fp = STDOUT;
} else {
   $fp = fopen($argv[1] . ".new", "w");
}

fwrite($fp, "<?php\n");
fwrite($fp, "\$CONFIG=");
print_array($CONFIG, 1, $fp);
fwrite($fp, ";\n");
fwrite($fp, "?>\n");
fclose($fp);

# ok - rename
if (! $dry_run) {
   if (file_exists($argv[1] . ".old")) {
      unlink($argv[1] . ".old");
   }
   rename($argv[1], $argv[1] . ".old");
   rename($argv[1] . ".new", $argv[1]);
}

?>
