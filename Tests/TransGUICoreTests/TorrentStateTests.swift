import Foundation
import Testing
import TransGUICore

/// Status interpretation, progress, errors and derived display values.
@Suite("Torrent state derivation")
struct TorrentStateTests {
    private func torrent(_ json: String) -> Torrent {
        try! JSONDecoder().decode(Torrent.self, from: Data(json.utf8))
    }

    @Test("Wire status maps to the display status")
    func displayStatus() {
        #expect(torrent(#"{"id":1,"status":0,"sizeWhenDone":100,"leftUntilDone":40}"#).displayStatus == .stopped)
        #expect(torrent(#"{"id":1,"status":0,"sizeWhenDone":100,"leftUntilDone":0}"#).displayStatus == .finished)
        #expect(torrent(#"{"id":1,"status":1}"#).displayStatus == .waiting)
        #expect(torrent(#"{"id":1,"status":2}"#).displayStatus == .verifying)
        #expect(torrent(#"{"id":1,"status":3}"#).displayStatus == .waiting)
        #expect(torrent(#"{"id":1,"status":4}"#).displayStatus == .downloading)
        #expect(torrent(#"{"id":1,"status":5}"#).displayStatus == .waiting)
        #expect(torrent(#"{"id":1,"status":6}"#).displayStatus == .seeding)
    }

    @Test("Progress fractions")
    func progress() {
        let downloading = torrent(
            #"{"id":1,"status":4,"sizeWhenDone":1000,"leftUntilDone":400}"#)
        #expect(downloading.progressFraction == 0.6)
        #expect(downloading.progressText == "60.0%")

        let verifying = torrent(
            #"{"id":1,"status":2,"sizeWhenDone":1000,"leftUntilDone":1000,"recheckProgress":0.25}"#)
        #expect(verifying.progressFraction == 0.25)

        // Metadata not yet fetched (no files chosen): metadata progress.
        let metadata = torrent(#"{"id":1,"status":4,"sizeWhenDone":0,"metadataPercentComplete":0.5}"#)
        #expect(metadata.progressFraction == 0.5)
    }

    @Test("ETA is recomputed from the current speed while downloading")
    func effectiveEta() {
        let t = torrent(#"{"id":1,"status":4,"rateDownload":100,"leftUntilDone":500,"eta":99}"#)
        #expect(t.effectiveEta == 5)
        let idle = torrent(#"{"id":1,"status":0,"eta":-1}"#)
        #expect(idle.effectiveEta == nil)
    }

    @Test("Global and tracker errors merge like the reference app")
    func errors() {
        let global = torrent(#"{"id":1,"errorString":"disk full"}"#)
        #expect(global.effectiveError == "disk full")
        #expect(global.hasGlobalError)

        let trackerOnly = torrent(
            """
            {"id":1,"errorString":"","trackerStats":[
              {"hasAnnounced":true,"lastAnnounceSucceeded":false,"lastAnnounceResult":"Failure"}]}
            """)
        #expect(trackerOnly.effectiveError == "Failure")
        #expect(!trackerOnly.hasGlobalError)

        let recovered = torrent(
            """
            {"id":1,"errorString":"","trackerStats":[
              {"hasAnnounced":true,"lastAnnounceSucceeded":false,"lastAnnounceResult":"Failure"},
              {"hasAnnounced":true,"lastAnnounceSucceeded":true,"lastAnnounceResult":"Success"}]}
            """)
        #expect(recovered.effectiveError == nil)
    }

    @Test("Active/complete flags and filter classification")
    func flags() {
        let active = torrent(#"{"id":1,"status":4,"rateDownload":10}"#)
        #expect(active.isActive)
        #expect(FilterID.downloading.matches(active))
        #expect(FilterID.active.matches(active))
        #expect(!FilterID.inactive.matches(active))

        let stoppedIncomplete = torrent(
            #"{"id":1,"status":0,"sizeWhenDone":100,"leftUntilDone":10}"#)
        #expect(FilterID.stopped.matches(stoppedIncomplete))
        #expect(!FilterID.completed.matches(stoppedIncomplete))

        let finished = torrent(#"{"id":1,"status":0,"sizeWhenDone":100,"leftUntilDone":0}"#)
        #expect(FilterID.completed.matches(finished))
        #expect(FilterID.stopped.matches(finished))

        let seeding = torrent(#"{"id":1,"status":6}"#)
        #expect(FilterID.completed.matches(seeding))
        #expect(!FilterID.stopped.matches(seeding))
    }

    @Test("Waiting filter covers queued check and queued download only")
    func waitingFilter() {
        #expect(FilterID.waiting.matches(torrent(#"{"id":1,"status":1}"#)))
        #expect(FilterID.waiting.matches(torrent(#"{"id":1,"status":2}"#)))
        #expect(FilterID.waiting.matches(torrent(#"{"id":1,"status":3}"#)))
        #expect(!FilterID.waiting.matches(torrent(#"{"id":1,"status":5}"#)))
        #expect(!FilterID.waiting.matches(torrent(#"{"id":1,"status":4}"#)))
    }

    @Test("Seeds and peers column text")
    func seedsPeersText() {
        let known = torrent(
            """
            {"id":1,"peersSendingToUs":5,"peersGettingFromUs":12,
             "trackerStats":[{"seederCount":10,"leecherCount":15}]}
            """)
        #expect(known.seedsText == "5/10")
        #expect(known.peersText == "12/15")
        #expect(known.seedsSort == 10)
        #expect(known.peersSort == 15)

        let swarmSmaller = torrent(
            """
            {"id":1,"peersSendingToUs":5,"peersGettingFromUs":12,
             "trackerStats":[{"seederCount":10,"leecherCount":8}]}
            """)
        #expect(swarmSmaller.peersText == "12/8 (other peers)")

        let unknown = torrent(#"{"id":1,"peersSendingToUs":5,"peersGettingFromUs":12}"#)
        #expect(unknown.seedsText == "5")
        #expect(unknown.peersText == "12")
    }

    @Test("File wanted/priority accessors are bounds-checked")
    func fileAccessors() {
        let t = torrent(#"{"id":1,"wanted":[1,0],"priorities":[-1000,1]}"#)
        #expect(t.isWanted(0))
        #expect(!t.isWanted(1))
        #expect(t.isWanted(99))  // out of range: default wanted
        #expect(t.filePriority(0) == -1000)
        #expect(t.filePriority(1) == 1)
        #expect(t.filePriority(99) == 0)
    }

    @Test("Labels render comma-separated")
    func labels() {
        let t = torrent(#"{"id":1,"labels":["tv","hd"]}"#)
        #expect(t.labelsText == "tv, hd")
        #expect(torrent(#"{"id":1}"#).labelsText == "")
    }
}
