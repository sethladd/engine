// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "flutter/fml/platform/darwin/message_loop_darwin.h"

#include <CoreFoundation/CFRunLoop.h>
#include <Foundation/Foundation.h>

namespace fml {

static constexpr CFTimeInterval kDistantFuture = 1.0e10;

MessageLoopDarwin::MessageLoopDarwin()
    : running_(false), loop_((CFRunLoopRef)CFRetain(CFRunLoopGetCurrent())) {
  FTL_DCHECK(loop_ != nullptr);

  // Setup the delayed wake source.
  CFRunLoopTimerContext timer_context = {
      .info = this,
  };
  delayed_wake_timer_.Reset(CFRunLoopTimerCreate(
      kCFAllocatorDefault, kDistantFuture /* fire date */,
      HUGE_VAL /* interval */, 0 /* flags */, 0 /* order */,
      reinterpret_cast<CFRunLoopTimerCallBack>(&MessageLoopDarwin::OnTimerFire)
      /* callout */,
      &timer_context /* context */));
  FTL_DCHECK(delayed_wake_timer_ != nullptr);
  CFRunLoopAddTimer(loop_, delayed_wake_timer_, kCFRunLoopCommonModes);
}

MessageLoopDarwin::~MessageLoopDarwin() {
  CFRunLoopTimerInvalidate(delayed_wake_timer_);
  CFRunLoopRemoveTimer(loop_, delayed_wake_timer_, kCFRunLoopCommonModes);
}

void MessageLoopDarwin::Run() {
  FTL_DCHECK(loop_ == CFRunLoopGetCurrent());

  running_ = true;

  while (running_) {
    @autoreleasepool {
      int result =
          CFRunLoopRunInMode(kCFRunLoopDefaultMode, kDistantFuture, YES);
      if (result == kCFRunLoopRunStopped || result == kCFRunLoopRunFinished) {
        // This handles the case where the loop is terminated using
        // CoreFoundation APIs.
        @autoreleasepool {
          RunExpiredTasksNow();
        }
        running_ = false;
      }
    }
  }
}

void MessageLoopDarwin::Terminate() {
  running_ = false;
  CFRunLoopStop(loop_);
}

void MessageLoopDarwin::WakeUp(ftl::TimePoint time_point) {
  // Rearm the timer. The time bases used by CoreFoundation and FTL are
  // different and must be accounted for.
  CFRunLoopTimerSetNextFireDate(
      delayed_wake_timer_,
      CFAbsoluteTimeGetCurrent() +
          (time_point - ftl::TimePoint::Now()).ToSecondsF());
}

void MessageLoopDarwin::OnTimerFire(CFRunLoopTimerRef timer,
                                    MessageLoopDarwin* loop) {
  @autoreleasepool {
    // RunExpiredTasksNow rearms the timer as appropriate via a call to WakeUp.
    loop->RunExpiredTasksNow();
  }
}

}  // namespace fml
