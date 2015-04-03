#!/usr/bin/python

"""usage: python stylechecker.py /path/to/the/c/code"""

import os
import sys
import string
import re

WHITE = '\033[97m'
CYAN = '\033[96m'
BLUE = '\033[94m'
GREEN = '\033[92m'
YELLOW = '\033[93m'
RED = '\033[91m'
ENDC = '\033[0m'

def check_file(file):
    if re.search('\.[c|h]$', file) == None:
        return

    f = open(file)
    i = 1
    file_name_printed = False

    for line in f:
        line = line.replace('\n', '')

        # check the number of columns greater than 80
        if len(line) > 80:
            if not file_name_printed:
                print RED + file + ':' + ENDC
                file_name_printed = True
            print (GREEN + '    [>80]:' + BLUE + ' #%d(%d)' + WHITE + ':%s') % (i, len(line), line) + ENDC

        # check the last space in the end of line
        if re.match(r'.*\s$', line):
            if not file_name_printed:
                print RED + file + ':' + ENDC
                file_name_printed = True
            print (GREEN + '    [SPACE]:' + BLUE + ' #%d(%d)' + WHITE + ':%s') % (i, len(line), line) + ENDC

        # check the TAB key
        if string.find(line, '\t') >= 0:
            if not file_name_printed:
                print RED + file + ':' + ENDC
                file_name_printed = True
            print (YELLOW + '    [TAB]:' + BLUE + ' #%d(%d)' + WHITE + ':%s') % (i, len(line), line) + ENDC

        # check blank lines
        if line.isspace():
            if not file_name_printed:
                print RED + file + ':' + ENDC
                file_name_printed = True
            print (CYAN + '    [BLK]:' + BLUE + ' #%d(%d)' + WHITE + ':%s') % (i, len(line), line) + ENDC

        i = i + 1

    f.close()

def walk_dir(dir):
    for root, dirs, files in os.walk(dir):
        for f in files:
            s = root + '/' + f
            check_file(s)

    for d in dirs:
        walk_dir(d)

def usage():
    print """
Usage: stylechecker.py file or dir

    python stylechecker.py /path/to/the/c/code
        or
    python stylechecker.py /file/of/c/code """

    sys.exit(1)

### main
if len(sys.argv) == 2:
    PATH = sys.argv[1]

    if os.path.isfile(PATH):
        check_file(PATH)
    elif os.path.isdir(PATH):
        walk_dir(PATH)
    else:
        print RED + "Check the %s is file or dir" % PATH + ENDC
else:
    usage()
