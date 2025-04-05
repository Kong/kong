# ast-grep

`ast-grep` is a tool for querying source code in a (relatively)
language-agnostic manner. It allows us to write lint rules that target patterns
that are specific to our codebase and therefore not covered by tools like
`luacheck`.

## Installing ast-grep

See the [installation docs](https://ast-grep.github.io/guide/quick-start.html#installation)
for guidance.


## Crafting a New Lint Rule

The workflow for writing a new lint rule looks like this:

1. Draft your rule at `.ci/ast-grep/rules/${name}.yml`
    * Use `ast-grep scan --filter ${name} [paths...]` to evaluate your rule's behavior
2. Write tests for the rule in `.ci/ast-grep/tests/${name}-test.yml`
    * Make sure to fill out several `valid` and `invalid` code snippets
    * Use `ast-grep test --interactive`* to test the rule
3. `git add .gi/ast-grep && git commit ...`

\* `ast-grep test` uses a file snapshot testing pattern. Almost any time a rule
or test is created/modified, the snapshots must be updated. The `--interactive`
flag for `ast-grep test` will prompt you to accept these updates. The snapshots
provide very granular testing for rule behavior, but for many cases where we
just care about whether or not a rule matches a certain snippet of code, they
can be overkill. Use `ast-grep --update-all` to automatically accept and save
new snapshots.

## CI

`ast-grep` is executed in the ([ast-grep lint
workflow](/.github/workflows/ast-grep.yml)). In addition to running the linter,
this workflow also performs self-tests and ensures that all existing rules are
well-formed and have tests associated with them.

### Links

* [ast-grep website and documentation](https://ast-grep.github.io)
* [ast-grep source code](https://github.com/ast-grep/ast-grep)

#!/bin/bash

# Base URL for RouteViews archive
BASE_URL="http://archive.routeviews.org/bgpdata"

# Current working directory
RIB_DIR=$(pwd)

# Get yesterday's date in the format YYYY.MM and YYYYMMDD
YEAR_MONTH=$(date -d "yesterday" "+%Y.%m")
DAY=$(date -d "yesterday" "+%Y%m%d")

# Construct the URL for the previous day at 10:00
RIB_URL="$BASE_URL/$YEAR_MONTH/RIBS/rib.$DAY.1000.bz2"

# Hardcoded fallback URL
HARDCODED_URL="http://archive.routeviews.org/bgpdata/2023.08/RIBS/rib.20230807.1000.bz2"

# Filename to save the downloaded RIB
DOWNLOAD_PATH="$RIB_DIR/rib.$DAY.1000.bz2"

# Extracted RIB filename
EXTRACTED_RIB_FILE="$RIB_DIR/rib.$DAY.1000"

# Processed RIB filename
PROCESSED_RIB="$RIB_DIR/processed_rib.txt"

# Download the RIB file
echo "Downloading RIB data from $RIB_URL..."
curl -o $DOWNLOAD_PATH $RIB_URL

# Check if download was successful
if [ $? -ne 0 ]; then
    echo "Failed to download RIB data from the generated URL."
    echo "Falling back to hardcoded URL: $HARDCODED_URL..."
    curl -o $DOWNLOAD_PATH $HARDCODED_URL
    if [ $? -ne 0 ]; then
        echo "Failed to download RIB data from hardcoded URL as well."
        exit 1
    fi
fi

echo "Extracting RIB data from $DOWNLOAD_PATH..."
# Decompress the RIB data
bunzip2 $DOWNLOAD_PATH

# Check if decompression was successful
if [ $? -ne 0 ]; then
    echo "Failed to extract RIB data."
    exit 1
fi

# Process the RIB data
echo "Processing RIB data with bgpdump..."
bgpdump $EXTRACTED_RIB_FILE > $PROCESSED_RIB

# Check if processing was successful
if [ $? -ne 0 ]; then
    echo "Failed to process RIB data with bgpdump."
    exit 1
fi

rm rib*

echo "RIB data processed and saved to $PROCESSED_RIB"


exit 0
Free delivery
Free returns
Warranty
Meta
Meta
Profile picture for Airlangga Yudhoyono
​
Back to Quest Legal
QUEST
Horizon Worlds Third Party Notices
THE FOLLOWING SETS FORTH ATTRIBUTION NOTICES FOR THIRD PARTY SOFTWARE THAT MAY BE CONTAINED IN PORTIONS OF THIS META PRODUCT.
SimpleJSON

https://github.com/Bunny83/SimpleJSON

              The following software may be included in this product:
              SimpleJSON.
              This software contains the following license and notice below:

              The MIT License (MIT)

              Copyright (c) 2012-2017 Markus Göbel (Bunny83)

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
            
Code Cite

https://github.com/shanecelis/code-cite

              The following software may be included in this product: Code Cite.
              This software contains the following license and notice below:

              Copyright 2017 Shane Celis

              Permission is hereby granted, free of charge, to any person obtaining a
              copy of this software and associated documentation files (the "Software"),
              to deal in the Software without restriction, including without limitation
              the rights to use, copy, modify, merge, publish, distribute, sublicense,
              and/or sell copies of the Software, and to permit persons to whom the
              Software is furnished to do so, subject to the following conditions:

              The above copyright notice and this permission notice shall be included
              in all copies or substantial portions of the Software.

              THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
              OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
              MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
              IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
              CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
              TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
              SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
            
Code Snippet by user jistyles for Sharing is caring: Hiding optional material parameters

https://forum.unity.com/threads/sharing-is-caring-hiding-optional-material-parameters.349952/

              The following software may be included in this product: Code Snippet
              by user jistyles for Sharing is caring: Hiding optional material
              parameters.
              This software contains the following license and notice below:

              Copyright (c) 2015 jistyles
              Released as "public domain, no restrictions, no requirements, no support"

              https://forum.unity.com/threads/sharing-is-caring-hiding-optional-material-parameters.349952/
Easing Equations by Robert Penner

http://robertpenner.com/easing/

              The following software may be included in this product: Easing
              Equations by Robert Penner.
              This software contains the following
              license and notice below:

              BSD LicenseCopyright © 2001 Robert PennerRedistribution and use in
              source and binary forms, with or without modification, are permitted
              provided that the following conditions are met:Redistributions of
              source code must retain the above copyright notice, this list of
              conditions and the following disclaimer.Redistributions in binary
              form must reproduce the above copyright notice, this list of
              conditions and the following disclaimer in the documentation and/or
              other materials provided with the distribution.Neither the name of
              the author nor the names of contributors may be used to endorse or
              promote products derived from this software without specific prior
              written permission.

              THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS
              AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,
              INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
              AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL
              THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
              INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
              NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
              DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
              THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
              (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
              OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
            
Editor Script by Nick Gravelin

https://github.com/k1lly0u/RustEdit-Unity/tree/master/Library/PackageCache/com.unity.textmeshpro%402.0.1/Scripts/Editor

              The following software may be included in this product: Editor Script by Nick Gravelin.
              This software contains the following license and notice below:

              * Copyright (c) 2014, Nick Gravelyn.
              *
              * This software is provided 'as-is', without any express or implied
              * warranty. In no event will the authors be held liable for any damages
              * arising from the use of this software.
              *
              * Permission is granted to anyone to use this software for any purpose,
              * including commercial applications, and to alter it and redistribute it
              * freely, subject to the following restrictions:
              *
              * 1. The origin of this software must not be misrepresented; you must not
              * claim that you wrote the original software. If you use this software
              * in a product, an acknowledgment in the product documentation would be
              * appreciated but is not required.
              *
              * 2. Altered source versions must be plainly marked as such, and must not be
              * misrepresented as being the original software.
              *
              * 3. This notice may not be removed or altered from any source
              * distribution.
              */
            
Google Protocol

https://github.com/protocolbuffers/protobuf

              The following software may be included in this product: Google Protobuf.
              This software contains the following license and notice below:
              Copyright 2008 Google Inc. All rights reserved.

              Redistribution and use in source and binary forms, with or without
              modification, are permitted provided that the following conditions are
              met:

              * Redistributions of source code must retain the above copyright
              notice, this list of conditions and the following disclaimer.
              * Redistributions in binary form must reproduce the above
              copyright notice, this list of conditions and the following disclaimer
              in the documentation and/or other materials provided with the
              distribution.
              * Neither the name of Google Inc. nor the names of its
              contributors may be used to endorse or promote products derived from
              this software without specific prior written permission.

              THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
              "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
              LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
              A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
              OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
              SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
              LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
              DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
              THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
              (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
              OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

              Code generated by the Protocol Buffer compiler is owned by the owner
              of the input file used when generating it. This code is not
              standalone and requires a support library to be linked with it. This
              support library is itself covered by the above license.
            
Graphy

https://github.com/Tayx94/graphy

              The following software may be included in this product: Graphy.
              This software contains the following license and notice below:

              MIT License

              Copyright (c) 2018 MartÃn Pane

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
            
Jetbrains resharper-unity

https://github.com/JetBrains/resharper-unity

              The following software may be included in this product: Jetbrains resharper-unity.
              This software contains the following license and notice below:
              Apache License
              Version 2.0, January 2004
              https://www.apache.org/licenses/
LeanTween 2.45

http://dentedpixel.com/LeanTweenDocumentation/classes/LeanTween.html

              The following software may be included in this product: LeanTween 2.45.
              This software contains the following license and notice below:


              // The MIT License (MIT)
              //
              // Copyright (c) 2017 Russell Savage - Dented Pixel
              //
              // Permission is hereby granted, free of charge, to any person obtaining a copy
              // of this software and associated documentation files (the "Software"), to deal
              // in the Software without restriction, including without limitation the rights
              // to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
              // copies of the Software, and to permit persons to whom the Software is
              // furnished to do so, subject to the following conditions:
              //
              // The above copyright notice and this permission notice shall be included in all
              // copies or substantial portions of the Software.
              //
              // THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
              // IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
              // FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
              // AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
              // LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
              // OUT OF OR
              The following software may be included in this product: mono.reflection by Jb Evain.
              This software contains the following license and notice below:

              // Author:
              // Jb Evain (jbevain@novell.com)
              //
              // (C) 2009 - 2010 Novell, Inc. (http://www.novell.com)
              //
              // Permission is hereby granted, free of charge, to any person obtaining
              // a copy of this software and associated documentation files (the
              // "Software"), to deal in the Software without restriction, including
              // without limitation the rights to use, copy, modify, merge, publish,
              // distribute, sublicense, and/or sell copies of the Software, and to
              // permit persons to whom the Software is furnished to do so, subject to
              // the following conditions:
              //
              // The above copyright notice and this permission notice shall be
              // included in all copies or substantial portions of the Software.
              //
              // THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
              // EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
              // MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
              // NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
              // LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
              // OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
              // WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
            
PopcornFX Runtime SDK

https://www.popcornfx.com/sdk/

              The following software may be included in this product:
              PopcornFX Runtime SDK.
              This software contains the following notice below:
              Realtime VFX powered by PopcornFX - © 2022 Persistant Studios.
            
Snapshot Games Color Picker for Unity UI

https://github.com/SnapshotGames/cui_color_picker

              The following software may be included in this product:
              Snapshot Games Color Picker for Unity UI.
              This software contains the following license and notice below:

              Copyright (c) 2016 Snapshot Games Inc.

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
            
Unity Built in shaders

https://unity3d.com/get-unity/download/archive

              The following software may be included in this product: Unity Built in shaders.
              This software contains the following license and notice below:

              Copyright (c) 2016 Unity Technologies


              Permission is hereby granted, free of charge, to any person obtaining a copy of
              this software and associated documentation files (the "Software"), to deal in
              the Software without restriction, including without limitation the rights to
              use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
              of the Software, and to permit persons to whom the Software is furnished to do
              so, subject to the following conditions:


              The above copyright notice and this permission notice shall be included in all
              copies or substantial portions of the Software.


              THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
              IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
              FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
              COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
              IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
              CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
            
Unity.IO.Compression by Hitcents

https://github.com/Hitcents/Unity.IO.Compression

              The following software may be included in this product:
              Easing Equations by Unity.IO.Compression by Hitcents.
              This software contains the following license and notice below:Copyright (c) Hitcents

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
            
unity3d-runtime-debug-draw

https://github.com/jagt/unity3d-runtime-debug-draw

              License: Public Domain
            
Unity3D: MiniJSON

https://gist.github.com/darktable/1411710

              The following software may be included in this product: Unity3D: MiniJSON.
              This software contains the following license and notice below:
              /*
              * Copyright (c) 2013 Calvin Rien
              *
              * Based on the JSON parser by Patrick van Bergen
              * http://techblog.procurios.nl/k/618/news/view/14605/14863/How-do-I-write-my-own-parser-for-JSON.html
              *
              * Simplified it so that it doesn't throw exceptions
              * and can be used in Unity iPhone with maximum code stripping.
              *
              * Permission is hereby granted, free of charge, to any person obtaining
              * a copy of this software and associated documentation files (the
              * "Software"), to deal in the Software without restriction, including
              * without limitation the rights to use, copy, modify, merge, publish,
              * distribute, sublicense, and/or sell copies of the Software, and to
              * permit persons to whom the Software is furnished to do so, subject to
              * the following conditions:
              *
              * The above copyright notice and this permission notice shall be
              * included in all copies or substantial portions of the Software.
              *
              * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
              * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
              * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
              * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
              * CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
              * TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
              * SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
              */
            
Webgl-noise

https://github.com/stegu/webgl-noise/

              The following software may be included in this product: webgl-noise.
              This software contains the following license and notice below:

              Copyright (C) 2011 by Ashima Arts (Simplex noise)
              Copyright (C) 2011-2016 by Stefan Gustavson (Classic noise and others)

              Permission is hereby granted, free of charge, to any person obtaining a copy
              of this software and associated documentation files (the "Software"), to deal
              in the Software without restriction, including without limitation the rights
              to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
              copies of the Software, and to permit persons to whom the Software is
              furnished to do so, subject to the following conditions:

              The above copyright notice and this permission notice shall be included in
              all copies or substantial portions of the Software.

              THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
              IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
              FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
              AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
              LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
              OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
              THE SOFTWARE.
            
zlib

https://zlib.net/

              The following software may be included in this product: zlib.
              This software contains the following license and notice below:

              /* zlib.h -- interface of the 'zlib' general purpose compression library
              version 1.2.11, January 15th, 2017

              Copyright (C) 1995-2017 Jean-loup Gailly and Mark Adler

              This software is provided 'as-is', without any express or implied
              warranty. In no event will the authors be held liable for any damages
              arising from the use of this software.

              Permission is granted to anyone to use this software for any purpose,
              including commercial applications, and to alter it and redistribute it
              freely, subject to the following restrictions:

              1. The origin of this software must not be misrepresented; you must not
              claim that you wrote the original software. If you use this software
              in a product, an acknowledgment in the product documentation would be
              appreciated but is not required.
              2. Altered source versions must be plainly marked as such, and must not be
              misrepresented as being the original software.
              3. This notice may not be removed or altered from any source distribution.

              Jean-loup Gailly Mark Adler
              jloup@gzip.org madler@alumni.caltech.edu

              */
            
LEVEL UP WITH EXCLUSIVE NEWS FROM META
Be the first to get updates on Meta products, limited-time promotions, new game drops and more.
Email
By signing up you agree to receive updates and marketing messages (e.g. email, social, etc.) from Meta about Meta’s existing and future products and services.
You may withdraw your consent and unsubscribe at any time by clicking the unsubscribe link included in our messages.
Your subscription is subject to the Terms and Privacy Policy.
Meta
FacebookThreadsInstagramXYouTube
Meta Store
Ray-Ban Meta glasses
Meta Quest
Accessories
Apps and games
Meta Quest gift cards
Refurbished Meta Quest 3
Refurbished Ray-Ban Meta glasses
Meta Quest: Play now. Pay later.
Meta Warranty Plus
Meta for Work
Meta for Education
Meta Quest referrals
Education discount
Store support and legal
Community
Our actions
About us
Site terms and policies
App support
United States (English)
META QUEST

Meta Quest: *Parents:* Important guidance & safety warnings for children’s use here. Using Meta Quest requires an account and is subject to requirements that include a minimum age of 10 (requirements may vary by country). See meta.com/quest/terms and the parent’s info page at meta.com/quest/parent-info. Certain apps, games and experiences may be suitable for a more mature audience. META QUEST FEATURES, FUNCTIONALITY, AND CONTENT NOTICE: Features, functionality and content are subject to change or withdrawal at any time, may not be available in all areas or languages or may be restricted; may require enabled software or service activation, and additional terms, conditions and/or charges may apply.

META QUEST IMPORTANT SAFETY NOTICE https://www.meta.com/quest/quest-2-facial-interface-recall/.
https://www.facebook.com/100064478568105/posts/pfbid02FyXKkgVVrSRN34gE35wFDPGNyJw7hbdRtnToD7i4g76T8MDYmGBJc4XX2AHsDanel/

https://www.facebook.com/100064858029871/posts/pfbid05Qe46i1xUXEwz2Rp88zfwJgoUWptQ9BAtBPVQsTDDFg72eJwQ4iw6UkaKkzJzs71l/?app=fbl

https://www.facebook.com/reel/1289323665627918/

1 https://mydramawave.com?redirect=%2Fdetail%3Fid%3DPe58eH2nnS pid=360security_int&af_sub1=zTfdHYVArGicLsEzj5jqj1JUohR.tt.1&af_sub2=E_C_P_Cs4B8xRyGUhXe-WMHyNykhIMEDUflEQ8PmeAHKSlfR7-ONJzVB-oHwkJ3YSPn9UrKgRJxNjFA_MaeuoPtSIC8p9sZm8Yi0RERpUZMo_FFDC7ZbYhZqsVVjUCydW1qJNXEu-81tLsSjt8r1cCCKKaEY1EwLSRWbC3LHzWB7lx2Dlxc9G8ohpa2vVN12QME1nNrtwii4ovswbxHe1_EvsxrAfa3jmJmfbXFoqY5zKY1SGFIFbjt5MdZpR7DV3ZFQ1LgWP0YUGpJgM2iR9S-IVFoqoSBHYyLjA&af_sub3=101.255.105.201&af_sub4=Mozilla%2F5.0%20(Linux%3B%20Android%2012%3B%20SM-A315G%20Build%2FSP1A.210812.016%3B%20)%20AppleWebKit%2F537.36%20(KHTML%2C%20like%20Gecko)%20Version%2F4.0%20Chrome%2F132.0.6834.166%20Mobile%20Safari%2F537.36%20trill_380803%20JsSdk%2F1.0%20NetType%2FWIFI%20Channel%2Fgoogleplay%20AppName%2Ftrill%20app_version%2F38.8.3%20ByteLocale%2Fid-ID%20ByteFullLocale%2Fid-ID%20Region%2FID%20AppId%2F1180%20Spark%2F1.7.2%20AppVersion%2F38.8.3%20PIA%2F2.5.3%20BytedanceWebview%2Fd8a21c6&af_sub5=3&c=KunlunCQ_TT_WXY%7CW2aPage%5B1960%5D_ID_id_Cinta%20di%20Hembusan%20Senja%7CEV-SEARCH_20250221_Webpage_Pe58eH2nnS_02&af_c_id=1824664337378353&af_ad=BJ-LITTB-(19-26)-ID-%E6%B7%B7%E5%89%AA-liuhuan-0113-2_contentid%5BPe58eH2nnS%5D.mp4_001&af_ad_id=1824664328370274&af_adset=ID_%E7%88%B1%E5%9C%A8%E9%BB%84%E6%98%8F%E6%99%9A%E9%A3%8E%E6%97%B6_03&af_adset_id=1824664338204674&af_channel=null&af_siteid=1960&af_sub_siteid=0_0_0

Financing Options. You may be offered financing options for your Meta purchases. Learn more here.

***Based on the graphic performance of the Qualcomm Snapdragon XR2 Gen 2 vs XR2 Gen 1 on Meta Quest 2

RAY-BAN META

Meta AI and voice commands only in select countries and languages. Please check local availability. Meta account and Meta View App required. For ages 13+ only. Requires compatible phone with Android or iOS operating system plus wireless internet access. Features, functionality and content are subject to change or withdrawal at any time. Additional account registration, terms and fees may apply. Software updates may be required. Performance may vary based on user location, device battery, temperature, internet connectivity and interference from other devices, plus other factors. User must comply with all applicable local laws and regulations, especially relating to privacy. May interfere with personal medical devices. Check manufacturer Safety & Warranty Guide and FAQs for more product information, including battery life.

©2025 Meta.
