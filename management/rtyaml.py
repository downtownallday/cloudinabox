# this "rtyaml" proxies to pyyaml, avoiding an install

import yaml

def load(fn):
    if type(fn) is str:
        with open(fn) as fp:
            return yaml.load(fp, Loader=yaml.FullLoader)
    else:
        return yaml.load(fn, Loader=yaml.FullLoader)

def dump(x):
    return yaml.dump(x)
