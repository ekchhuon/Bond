//
//  The MIT License (MIT)
//
//  Copyright (c) 2016 Srdan Rasic (@srdanrasic)
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

#if os(iOS) || os(tvOS)

import UIKit
import ReactiveKit

public extension ReactiveExtensions where Base: UITextField {

    var text: DynamicSubject<String?> {
        return dynamicSubject(
            signal: controlEvents(.allEditingEvents).eraseType(),
            get: { $0.text },
            set: { $0.text = $1 }
        )
    }

    var attributedText: DynamicSubject<NSAttributedString?> {
        return dynamicSubject(
            signal: controlEvents(.allEditingEvents).eraseType(),
            get: { $0.attributedText },
            set: { $0.attributedText = $1 }
        )
    }

    var textColor: Bond<UIColor?> {
        return bond { $0.textColor = $1 }
    }
}

extension UITextField: BindableProtocol {

    public func bind(signal: Signal<String?, NoError>) -> Disposable {
        return reactive.text.bind(signal: signal)
    }
}

#endif
