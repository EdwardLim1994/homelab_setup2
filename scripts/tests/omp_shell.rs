use super::*;
use crate::util::testutil::*;

#[test]
fn scale_down_runs_once() {
    let _g = lock();
    let _p = EmptyPath::new();
    let flag = AtomicBool::new(false);
    scale_down("omp", "omp", &flag);
    assert!(flag.load(Ordering::SeqCst));
    scale_down("omp", "omp", &flag); // second call is a no-op
    assert!(flag.load(Ordering::SeqCst));
}

// ctrlc::set_handler may only be installed once per process, so this is
// the single test that calls run().
#[test]
fn run_tolerates_missing_kubectl() {
    let _g = lock();
    let _p = EmptyPath::new();
    assert_eq!(run().unwrap(), 0);
}
