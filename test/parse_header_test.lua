local testcase = require('testcase')
local parse = require('net.http.parse')
local parse_header = parse.header

function testcase.parse_header()
    -- test that parse header lines that terminate by CRLF
    local msg = 'Foo: foo-value\r\n' .. 'Bar: bar-value\r\n' .. '\r\n'
    local header = {}
    assert.equal(parse_header(msg, header), #msg)
    local kv_foo = {ord = 1, key = 'foo', vals = {'foo-value'}}
    local kv_bar = {ord = 2, key = 'bar', vals = {'bar-value'}}
    assert.equal(header, {kv_foo, kv_bar, foo = kv_foo, bar = kv_bar})

    -- test that parse header lines that terminate by LF
    msg = 'Foo: foo-value\n' .. 'Bar: bar-value\n' .. '\n'
    header = {}
    assert.equal(parse_header(msg, header), #msg)
    assert.equal(header, {kv_foo, kv_bar, foo = kv_foo, bar = kv_bar})

    -- test that ignore empty-value
    msg = table.concat({
        'Foo: foo-value', 'Bar: ', 'Baz: baz-value', 'Qux: \n\n'}, '\n')
    header = {}
    assert.equal(parse_header(msg, header), #msg)
    local kv_baz = {ord = 2, key = 'baz', vals = {'baz-value'}}
    assert.equal(header, {kv_foo, kv_baz, foo = kv_foo, baz = kv_baz})

    -- test that insert multiple same name headers into array
    msg = table.concat({
        'Hello: world!', 'Host: example1.com', 'Host: example2.com',
        'Host: example3.com',
        'Host: 1.example.com 2.example.com\t3.example.com\n\n'}, '\n')
    header = {}
    assert.equal(parse_header(msg, header), #msg)
    local kv_hello = {ord = 1, key = 'hello', vals = {'world!'}}
    local kv_host = {
        ord = 2,
        key = 'host',
        vals = {
            'example1.com', 'example2.com', 'example3.com',
            '1.example.com 2.example.com\t3.example.com'},
    }
    assert.equal(header, {kv_hello, kv_host, hello = kv_hello, host = kv_host})

    -- test that cannot parse header lines that not terminate by LF
    msg = 'Foo: foo-value\r' .. 'Bar: bar-value\r' .. '\r'
    assert.equal(parse_header(msg, {}), parse.EEOL)

    -- test that parse header lines from specified offset position
    local line = 'Hello world'
    msg = line .. 'Foo: foo-value\n' .. 'Bar: bar-value\n' .. '\n'
    header = {}
    assert.equal(parse_header(msg, header, #line), #msg)
    assert.equal(header, {kv_foo, kv_bar, foo = kv_foo, bar = kv_bar})

    -- test that limit the length of header line
    msg = 'Foo: foo-value\n' .. 'Bar: bar-value\n' .. '\n'
    assert.equal(parse_header(msg, {}, nil, 10), parse.EHDRLEN)

    -- test that limit the number of header line
    msg = table.concat({
        'Foo: foo-value', 'Bar: bar-value', 'Baz: baz-value',
        'Qux: qux-value\n\n'}, '\n')
    header = {}
    assert.equal(parse_header(msg, {}, nil, nil, 3), parse.EHDRNUM)
    assert.equal(parse_header(msg, header, nil, nil, 4), #msg)
    local kv_qux = {ord = 4, key = 'qux', vals = {'qux-value'}}
    kv_baz.ord = 3
    assert.equal(header, {
        kv_foo,
        kv_bar,
        kv_baz,
        kv_qux,
        foo = kv_foo,
        bar = kv_bar,
        baz = kv_baz,
        qux = kv_qux,
    })

    -- test that cannot parse invalide header name
    local VALID_HKEY = {
        --  NUL = EAGAIN
        true, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        --  LF = end of header
        true, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, nil, nil, nil,
        --        "                              (    )              ,              /
        '!', nil, '#', '$', '%', '&', '\'', nil, nil, '*', '+', nil, '-', '.',
        nil, '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
        --   :    ;    <    =    >    ?    @
        nil, nil, nil, nil, nil, nil, nil, 'a', 'b', 'c', 'd', 'e', 'f', 'g',
        'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u',
        'v', 'w', 'x', 'y', 'z', --   [    \    ]
        nil, nil, nil, '^', '_', '`', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h',
        'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v',
        'w', 'x', 'y', 'z', --   {         }
        nil, '|', nil, '~'}
    for i = 0x0, 0x7e do
        if not VALID_HKEY[i + 1] then
            local c = string.char(i)
            assert.equal(parse_header(c .. 'Host: example.com\n\n', {}),
                         parse.EHDRNAME)
        end
    end
    assert.equal(parse_header(' Host : example.com\n\n', {}), parse.EHDRNAME)
    assert.equal(parse_header('Host : example.com\n\n', {}), parse.EHDRNAME)

    -- test that cannot parse invalide header value
    local VCHAR = {
        nil, nil, nil, nil, nil, nil, nil, nil, nil, --  HT LF
        1, 1, nil, nil, --  CR
        1, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, --  SP !  "  #  $  %  &  '  (  )  *  +  ,  -  .  /
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        --  nil  1  2  3  4  5  6  7  8  9
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, --  :  ;  <  =  >  ?  @
        1, 1, 1, 1, 1, 1, 1,
        --  A  B  C  D  E  F  G  H  I  J  K  L  M  N  O  P  Q  R  S  T  U  V  W  X  Y
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        1, --  Z  [  \  ]  ^  _  `
        1, 1, 1, 1, 1, 1, 1,
        --  a  b  c  d  e  f  g  h  i  j  k  l  m  n  o  p  q  r  s  t  u  v  w  x  y
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        1, --  z  {  |  }  ~
        1, 1, 1, 1, 1}
    for i = 0x0, 0x7e do
        if not VCHAR[i + 1] then
            local c = string.char(i)
            assert.equal(parse_header('Host: ' .. c .. 'example.com\n\n', {}),
                         parse.EHDRVAL)
        end
    end
end
