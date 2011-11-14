Kindle The Economist
====================

Backstory
---------

I really enjoy reading The Economist. Unfortunately, for some reason every other print issue gets lost in the mail which
leaves me with the online version of the print edition on economist.com. Since the Kindle version of the Economist has to
be subscribed on top of the print edition and I don't see why I should pay for what is essentially the incompetence of
Economist logistics to read the magazine "offline", I wrote this little scraper script.

Requirements
------------

  * A valid The Economist subscriptions
  * Ruby 1.9.1+
  * ImageMagick

For conversion to mobi files:

  * kindlegen

For direct delivery to you kindle:

  * SMTP server credentials

Install
-------

1. Download the files from the git repository and put them anywhere on your harddrive.

2. Install the bundler Ruby gem:

   gem install bundler

3. Install all dependencies, open a prompt in the kindle-the-economist directory and execute:

   bundle install

4. If you don't have ImageMagick yet, download and install it from here: http://www.imagemagick.org/script/binary-releases.php
   Make sure the ImageMagick binaries (esp. identify and mogrify) are in the path.

5. You can download kindlegen free of charge here: http://www.amazon.com/gp/feature.html?ie=UTF8&docId=1000234621
   Put the binary (kindlegen or kindlegen.exe) in the ./bin directory of kindle-the-economist.

6. Rename config.yml.template to config.yml and change all config values appropriately. The only section strictly required
   is the "credentials" with your economist.com login information. All other sections are optional.

Run
---

Windows: Execute bin/kte.bat
Linux: Execute bin/kte.sh

If you run the script without any arguments, the current issue is downloaded. On both platforms you may pass one or more
specific issues (by date) for download like so:

  kte.[bat/sh] 2011-11-05 2011-11-12 ...