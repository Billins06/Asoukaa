path = 'src/modules/products/products.service.ts'
with open(path, 'rb') as f:
    data = f.read()

old = b".leftJoinAndSelect('product.categories', 'category')\r\n"
new = b".leftJoinAndSelect('product.categories', 'category')\r\n      .leftJoinAndSelect('product.vendor',     'vendor')\r\n"

count = data.count(old)
print('matches:', count)
if count != 1:
    raise SystemExit('expected exactly 1 match')

data = data.replace(old, new, 1)
with open(path, 'wb') as f:
    f.write(data)
print('OK')
