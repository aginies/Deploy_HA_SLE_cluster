#!/usr/bin/python3
from distutils.core import setup
import os

data_files = []
data_files.append(('share/hark/scenarios', ['scenarios/' + f for f in os.listdir('scenarios')]))
data_files.append(('share/hark/conf', ['conf/' + f for f in os.listdir('conf')]))
data_files.append(('share/hark/templates', ['templates/' + f for f in os.listdir('templates')]))

setup(name='Hark!',
      version='0.2',
      description='SLE HA VM creation / management tool',
      author='Antoine Ginies + Kristoffer Gronlund',
      author_email='aginies@suse.com, kgronlund@suse.com',
      url='https://github.com/aginies/Deploy_HA_SLE_cluster.git',
      scripts=['hark'],
      data_files=data_files,
      requires=['lxml', 'requests'])
