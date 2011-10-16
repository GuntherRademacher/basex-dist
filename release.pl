# Creates all files for a new release.
# 
# (C) BaseX Team 2005-11, ISC License

use warnings;
use strict;
use File::Copy;
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );

# home of launch4j
my $launch4j = "win/tools/launch4j/launch4jc.exe";
# home of nsis
my $nsis = "win/tools/nsis/makensis.exe /V1";
# versions
my $f = "";
my $v = "";

# prepare release
prepare();
# create installer
exe();
# create zip file
zip();
# finish release
finish();

# prepares a new release
sub prepare {
  print "* Prepare release\n";

  foreach my $file(glob("release/*")) {
    unlink($file);
  }
  mkdir("release");

  # extract pom version
  version();
  # create packages
  pkg("basex");
  pkg("basex-api");
  # create WAR file
  system("cd ../basex-api && mvn compile war:war");
  move("../basex-api/target/basex-api-$v.war", "release/basex.war");
}

# gets version from pom file
sub version {
  print "* Extract version from POM file\n";

  open(POM, "../basex/pom.xml") or die "pom.xml not found";
  while(my $l = <POM>) {
    next if $l !~ m|<version>(.*)</version>|;
    $v = $1;
    if (length($v) == 1) {
      $f = $v . ".0.0.0";
    } elsif (length($v) == 3) {
      $f = $v . ".0.0";
    } elsif (length($v) == 5) {
      $f = $v . ".0";
    } else {
      $f = substr($v, 0, 5).".".time();
    }
    last;
  }
  close(POM);
}

# packages both projects
sub pkg {
  my $name = shift;
  print "* Create $name-$v package\n";

  unlink("../$name/target/*.jar");
  system("cd ../$name && mvn install -q -DskipTests=true");
  move("../$name/target/$name-$v.jar", "release/$name.jar");
}

# modifies the launch4j xml
sub exe {
  print "* Create executable\n";

  open(L4J, "win/launch4j.xml");
  my @raw_data=<L4J>;
  open(L4JTMP, '>>release/launch4j.xml');
  (my $ff = $f) =~ s/-.*//;
  (my $vv = $v) =~ s/-.*//;
  foreach my $line (@raw_data) {
    $line =~ s/\$f/$ff/g;
    $line =~ s/\$v/$vv/g; 
    print L4JTMP $line;
  }
  close(L4J);
  close(L4JTMP);

  system("$launch4j release/launch4j.xml");
  unlink("release/launch4j.xml");
  move("BaseX.exe", "release/BaseX.exe");

  system($nsis." win/installer/BaseX.nsi");
  unlink("release/BaseX.exe");
}

# creates zip archive
sub zip {
  print "* Create ZIP file\n";

  my $zip = Archive::Zip->new();

  # Add directories
  my $name = "basex";
  $zip->addDirectory("$name/");
  $zip->addDirectory("$name/lib");
  $zip->addDirectory("$name/bin");
  $zip->addDirectory("$name/etc");
  $zip->addString("", "$name/.basex");

  # Add files from disk
  $zip->addFile("release/basex.jar", "$name/BaseX.jar");
  $zip->addFile("../$name/readme.txt", "$name/readme.txt");
  $zip->addFile("../$name/license.txt", "$name/license.txt");
  $zip->addFile("../$name/changelog.txt", "$name/changelog.txt");

  foreach my $file(glob("etc/*")) {
    $zip->addFile($file, "$name/$file");
  }
  $zip->addFile("release/basex-api.jar", "$name/lib/basex-api.jar");

  # bin folder
  foreach my $file(glob("bin/*")) {
    next if $file =~ /basexhttp.bat/;
    my $m = $zip->addFile($file, "$name/$file");
    $m->unixFileAttributes($file =~ /.bat$/ ? 0400 : 0700);
  }

  # add the start call in REST script
  # (needs to be done manually, as file is also modified by .nsi script)
  copy("bin/basexhttp.bat", "release/basexhttp.bat");
  open (REST,'>> release/basexhttp.bat');
  print REST 'java -cp "%CP%;." %VM% org.basex.api.BaseXHTTP %*';
  close(REST);

  $zip->addFile("release/basexhttp.bat", "$name/bin/basexhttp.bat");

  # lib folder
  foreach my $file(glob("../basex-api/lib/*")) {
    (my $target = $file) =~ s|.*/|lib/|;
    $zip->addFile($file, "$name/$target");
  }

  # save the zip file
  unless ($zip->writeToFileNamed("release/BaseX.zip") == AZ_OK ) {
    die "Could not write ZIP file.";
  }
  unlink("release/basexhttp.bat");
}

# finishes the new release
sub finish {
  print "* Finish release\n";

  $v =~ s/\.//g;
  move("release/BaseX.zip","release/BaseX$v.zip");
  move("release/basex.jar","release/BaseX$v.jar");
  move("release/basex.war","release/BaseX$v.war");
  move("win/installer/Setup.exe","release/BaseX$v.exe");
  unlink("release/basex-api.jar");
}
