import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class With10SecondDelay extends StatelessWidget {
  static runningFunction(String s) async {
    int sum = await doTheCalc();
    return "total sum is 55";
  }

  static Future<int> doTheCalc() {
    int sum = 0;
    for (int i = 1; i <= 10; i++) {
      sleep(Duration(seconds: 1));
      // await Future<void>.delayed(Duration(milliseconds: 1000));
      print(i);
      sum += i;
    }

    return Future.value(sum);
  }

  pauseFunction() async {
    //pause function is not async
    // print(await compute(runningFunction, ''));
    print(runningFunction(''));
  }

  @override
  Widget build(BuildContext context) {
    pauseFunction();
    return Material(
      child: Center(
        child: Center(
          child: Text(
            "Tnx for waiting 10 seconds : check console for response",
            style: TextStyle(
              fontSize: 50,
            ),
          ),
        ),
      ),
    );
  }
}
