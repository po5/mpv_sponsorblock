import urllib.request
import urllib.parse
import hashlib
import sqlite3
import random
import string
import json
import sys
import os

if sys.argv[1] in ["submit", "stats", "username"]:
    if not sys.argv[8]:
        if os.path.isfile(sys.argv[7]):
            with open(sys.argv[7]) as f:  
                uid = f.read()
        else:
            uid = "".join(random.choices(string.ascii_letters + string.digits, k=36))
            with open(sys.argv[7], "w") as f:
                f.write(uid)
    else:
        uid = sys.argv[8]

opener = urllib.request.build_opener()
opener.addheaders = [("User-Agent", "mpv_sponsorblock/1.0 (https://github.com/po5/mpv_sponsorblock)")]
urllib.request.install_opener(opener)

if sys.argv[1] == "ranges" and (not sys.argv[2] or not os.path.isfile(sys.argv[2])):
    sha = None
    if 3 <= int(sys.argv[6]) <= 32:
        sha = hashlib.sha256(sys.argv[4].encode()).hexdigest()[:int(sys.argv[6])]
    times = []
    try:
        response = urllib.request.urlopen(sys.argv[3] + "/api/skipSegments" + ("/" + sha + "?" if sha else "?videoID=" + sys.argv[4] + "&") + urllib.parse.urlencode([("categories", json.dumps(sys.argv[5].split(",")))]))
        segments = json.load(response)
        for segment in segments:
            if sha and sys.argv[4] != segment["videoID"]:
                continue
            if sha:
                for s in segment["segments"]:
                    times.append(str(s["segment"][0]) + "," + str(s["segment"][1]) + "," + s["UUID"] + "," + s["category"])
            else:
                times.append(str(segment["segment"][0]) + "," + str(segment["segment"][1]) + "," + segment["UUID"] + "," + segment["category"])
        print(":".join(times))
    except (TimeoutError, urllib.error.URLError) as e:
        print("error")
    except urllib.error.HTTPError as e:
        if e.code == 404:
            print("")
        else:
            print("error")
elif sys.argv[1] == "ranges":
    conn = sqlite3.connect(sys.argv[2])
    conn.row_factory = sqlite3.Row
    c = conn.cursor()
    times = []
    for category in sys.argv[5].split(","):
        c.execute("SELECT startTime, endTime, votes, UUID, category FROM sponsorTimes WHERE videoID = ? AND shadowHidden = 0 AND votes > -1 AND category = ?", (sys.argv[4], category))
        sponsors = c.fetchall()
        best = list(sponsors)
        dealtwith = []
        similar = []
        for sponsor_a in sponsors:
            for sponsor_b in sponsors:
                if sponsor_a is not sponsor_b and sponsor_a["startTime"] >= sponsor_b["startTime"] and sponsor_a["startTime"] <= sponsor_b["endTime"]:
                    similar.append([sponsor_a, sponsor_b])
                    if sponsor_a in best:
                        best.remove(sponsor_a)
                    if sponsor_b in best:
                        best.remove(sponsor_b)
        for sponsors_a in similar:
            if sponsors_a in dealtwith:
                continue
            group = set(sponsors_a)
            for sponsors_b in similar:
                if sponsors_b[0] in group or sponsors_b[1] in group:
                    group.add(sponsors_b[0])
                    group.add(sponsors_b[1])
                    dealtwith.append(sponsors_b)
            best.append(max(group, key=lambda x:x["votes"]))
        for time in best:
            times.append(str(time["startTime"]) + "," + str(time["endTime"]) + "," + time["UUID"] + "," + time["category"])
    print(":".join(times))
elif sys.argv[1] == "update":
    try:
        urllib.request.urlretrieve(sys.argv[3] + "/database.db", sys.argv[2] + ".tmp")
        os.replace(sys.argv[2] + ".tmp", sys.argv[2])
    except PermissionError:
        print("database update failed, file currently in use", file=sys.stderr)
        sys.exit(1)
    except ConnectionResetError:
        print("database update failed, connection reset", file=sys.stderr)
        sys.exit(1)
    except TimeoutError:
        print("database update failed, timed out", file=sys.stderr)
        sys.exit(1)
    except urllib.error.URLError:
        print("database update failed", file=sys.stderr)
        sys.exit(1)
elif sys.argv[1] == "submit":
    try:
        req = urllib.request.Request(sys.argv[3] + "/api/skipSegments", data=json.dumps({"videoID": sys.argv[4], "segments": [{"segment": [float(sys.argv[5]), float(sys.argv[6])], "category": sys.argv[9]}], "userID": uid}).encode(), headers={"Content-Type": "application/json"})
        response = urllib.request.urlopen(req)
        print("success")
    except urllib.error.HTTPError as e:
        print(e.code)
    except:
        print("error")
elif sys.argv[1] == "stats":
    try:
        if sys.argv[6]:
            urllib.request.urlopen(sys.argv[3] + "/api/viewedVideoSponsorTime?UUID=" + sys.argv[5])
        if sys.argv[9]:
            urllib.request.urlopen(sys.argv[3] + "/api/voteOnSponsorTime?UUID=" + sys.argv[5] + "&userID=" + uid + "&type=" + sys.argv[9])
    except:
        pass
elif sys.argv[1] == "username":
    try:
        data = urllib.parse.urlencode({"userID": uid, "userName": sys.argv[9]}).encode()
        req = urllib.request.Request(sys.argv[3] + "/api/setUsername", data=data)
        urllib.request.urlopen(req)
    except:
        pass
