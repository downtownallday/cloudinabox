# this "rtyaml" proxies to pyyaml, avoiding an install

import yaml

def load(fn):    
    return yaml.load(file(fn, 'r'))

def dump(x):
    return yaml.dump(x)
