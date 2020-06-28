# this is a dummy exclusiveprocess, which we don't need
class Lock:
    def __init__(self, die=False):
        self.die=die

    def forever(self):
        pass
    
