# Third-party notices

## BlurHash

BlurHashSwift implements the BlurHash algorithm, designed by Wolt and specified at
<https://github.com/woltapp/blurhash> (`Algorithm.md`). The Swift code here is written from that specification; no code
is copied from Wolt's implementations. The test fixtures are generated with Wolt's TypeScript implementation (the
`blurhash` npm package, a development dependency of `Scripts/` and `Web/` that is not part of the Swift package).

Wolt's BlurHash is published under the MIT License:

```text
MIT License

Copyright (c) 2018 Wolt Enterprises

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
