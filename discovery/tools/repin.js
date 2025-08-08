// Universal Android TLS pinning bypass for Frida
// Hooks common paths: OkHttp3/2, Conscrypt TrustManager, WebView, TrustKit.

Java.perform(function () {
    function safeHook(desc, fn) {
        try { fn(); } catch (e) { /* ignore */ }
    }

    safeHook('OkHttp3 CertificatePinner', function () {
        var Pinner = Java.use('okhttp3.CertificatePinner');
        Pinner.check.overload('java.lang.String', 'java.util.List').implementation = function (host, certs) {
            console.log('[Frida] OkHttp3 CertificatePinner.check bypass for', host);
            return;
        };
    });

    safeHook('OkHttp (old) CertificatePinner', function () {
        var Pinner2 = Java.use('com.squareup.okhttp.CertificatePinner');
        Pinner2.check.overload('java.lang.String', 'java.util.List').implementation = function (host, certs) {
            console.log('[Frida] OkHttp2 CertificatePinner.check bypass for', host);
            return;
        };
    });

    var TMI = [
        'com.android.org.conscrypt.TrustManagerImpl',
        'org.apache.harmony.xnet.provider.jsse.TrustManagerImpl',
        'com.google.android.gms.org.conscrypt.TrustManagerImpl'
    ];

    TMI.forEach(function (name) {
        safeHook(name + '.checkServerTrusted', function () {
            var Impl = Java.use(name);
            if (Impl.checkTrustedRecursive) {
                Impl.checkTrustedRecursive.implementation = function () {
                    console.log('[Frida] ' + name + '.checkTrustedRecursive bypass');
                    return arguments[0];
                };
            }
            if (Impl.checkServerTrusted) {
                var sigs = Impl.checkServerTrusted.overloads;
                for (var i = 0; i < sigs.length; i++) {
                    sigs[i].implementation = function () {
                        console.log('[Frida] ' + name + '.checkServerTrusted bypass');
                        return arguments[0];
                    };
                }
            }
        });
    });

    safeHook('X509TrustManagerExtensions', function () {
        var Exts = [
            'com.android.org.conscrypt.X509TrustManagerExtensions',
            'android.net.http.X509TrustManagerExtensions'
        ];
        Exts.forEach(function (n) {
            try {
                var X = Java.use(n);
                if (X.checkServerTrusted) {
                    X.checkServerTrusted.implementation = function () {
                        console.log('[Frida] ' + n + '.checkServerTrusted bypass');
                        return arguments[0];
                    };
                }
            } catch (e) {}
        });
    });

    safeHook('WebView SSL error', function () {
        var WVC = Java.use('android.webkit.WebViewClient');
        WVC.onReceivedSslError.implementation = function (view, handler, error) {
            console.log('[Frida] WebViewClient.onReceivedSslError -> proceed()');
            handler.proceed();
        };
    });

    safeHook('TrustKit', function () {
        var V = Java.use('com.datatheorem.android.trustkit.pinning.OkHostnameVerifier');
        V.verify.overload('java.lang.String', 'javax.net.ssl.SSLSession').implementation = function (host, session) {
            console.log('[Frida] TrustKit OkHostnameVerifier.verify bypass for', host);
            return true;
        };
    });
});
