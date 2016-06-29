# Standard library for install scripts.

def another_test():
    print('another_test:', source_dir())

@utility
def test_source_dir():
    print('test inner 1', source_dir())
    another_test()
    print('test inner 2', source_dir())
