import urllib.request
import sqlite3
import random
import string
import json
import sys
import os

if sys.argv[1] == "ranges" and not sys.argv[2]:
    times = []
    try:
        response = urllib.request.urlopen(f"{sys.argv[3]}/api/getVideoSponsorTimes?videoID={sys.argv[4]}")
        data = json.load(response)
        for time in data["sponsorTimes"]:
            times.append(f"{time[0]},{time[1]}")
        print(":".join(times))
    except:
        print("could not get sponsor times from API", file=sys.stderr)
elif sys.argv[1] == "ranges":
    conn = sqlite3.connect(sys.argv[2])
    conn.row_factory = sqlite3.Row
    c = conn.cursor()
    c.execute("SELECT startTime, endTime, votes FROM sponsorTimes WHERE videoID = ? AND shadowHidden = 0 AND votes > -1", (sys.argv[4],))
    times = []
    sponsors = c.fetchall()
    best = sponsors
    dealtwith = []
    similar = []
    for sponsor_a in sponsors:
        for sponsor_b in sponsors:
            if sponsor_a["startTime"] > sponsor_b["startTime"] and sponsor_a["startTime"] < sponsor_b["endTime"]:
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
        times.append(f"{time['startTime']},{time['endTime']}")
    print(":".join(times))
elif sys.argv[1] == "update":
    try:
        urllib.request.urlretrieve(f"{sys.argv[3]}/database.db", sys.argv[2] + ".tmp")
        os.replace(sys.argv[2] + ".tmp", sys.argv[2])
    except PermissionError:
        print("database update failed, file currently in use", file=sys.stderr)
    except ConnectionResetError:
        print("database update failed, connection reset", file=sys.stderr)
    except urllib.error.URLError:
        print("database update failed", file=sys.stderr)
elif sys.argv[1] == "submit":
    try:
        response = urllib.request.urlopen(f"{sys.argv[3]}/api/postVideoSponsorTimes?videoID={sys.argv[4]}&startTime={sys.argv[5]}&endTime={sys.argv[6]}&userID={sys.argv[7] or ''.join(random.choices(string.ascii_letters + string.digits, k=36))}")
        print("success")
    except urllib.error.HTTPError as e:
        print(e.code)
    except:
        print("error")