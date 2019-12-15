//
//  ViewController.swift
//  Workload
//
//  Created by Johannes Kadak on 21/09/2018.
//  Copyright © 2018 Johannes Kadak. All rights reserved.
//

import UIKit
import Alamofire

struct ApiResponse: Decodable {
  let total_grand: Int?
}

class ViewController: UIViewController, UITextFieldDelegate {

  //MARK: properties
  @IBOutlet weak var calculateButton: UIButton!
  @IBOutlet weak var inputText: UITextField!
  @IBOutlet weak var outputLabel: UILabel!
  @IBOutlet weak var hoursInMonthLabel: UILabel!
  @IBOutlet weak var togglHoursLabel: UILabel!
  @IBOutlet weak var apiTokenText: UITextField!
  @IBOutlet weak var workspaceIdText: UITextField!
  
  var togglWorkedInMonth: Int = 0
  var neededHours: Int = 0
  var hoursInMonth: Int = 0
  let hoursPerDay: Int = 8
  
  var apiToken: String = ""
  var workspaceId: Int = -1
  
  static let TOGGL_API_TOKEN = "togglApiToken"
  static let TOGGL_ACTIVE_WORKSPACE_ID = "togglActiveWorkspaceId"
  static let PERCENTAGE = "workloadPercentage"
  
  override func viewDidLoad() -> Void {
    super.viewDidLoad()
    // Do any additional setup after loading the view, typically from a nib.
    hoursInMonth = getHoursInMonth()
    hoursInMonthLabel.text = "/ \(hoursInMonth) h"
    
    inputText.delegate = self
    
    // Pull API token & main workspace ID from the UserDefaults
    let tok = UserDefaults.standard.string(forKey: ViewController.TOGGL_API_TOKEN) ?? ""

    apiToken = tok
    workspaceId = UserDefaults.standard.integer(forKey: ViewController.TOGGL_ACTIVE_WORKSPACE_ID)
    
    // Assign token & WS ID to UI
    apiTokenText.text = apiToken
    workspaceIdText.text = "\(workspaceId)"
    
    // Pull percentage from UserDefaults
    
    let percentage = UserDefaults.standard.integer(forKey: ViewController.PERCENTAGE)

    tryLoadToggl()
    
    
    
  }
  
  func tryLoadToggl() -> Void {
    if apiToken.count > 0 &&
      workspaceId > 0 {
      getTogglWorkedInMonth()
    }
  }
  
  func getCredential() -> String? {
    assert(apiToken.count > 0)
    let bearerToken = "\(apiToken):api_token"
    guard let data = bearerToken.data(using: String.Encoding.utf8) else {
      return nil
    }
    return data.base64EncodedString()
  }
  
  func getTogglWorkedInMonth() -> Void {
    assert(workspaceId > 0)

    // 1. figure out start & end of current calendar month
    let calendar = NSCalendar.current
    let components = calendar.dateComponents([.year, .month], from: Date())
    
    var endComponents = DateComponents(calendar: calendar)
    endComponents.month = 1
    endComponents.day = -1

    guard let start = calendar.date(from: components) else { return }
    guard let end = calendar.date(byAdding: endComponents, to: start) else { return }
    
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"

    // 2. construct query string
    let params: Parameters = [
      "user_agent": "wsdf294@gmail.com - net.boxmein.Workload test app",  // custom UA
      "workspace_id": workspaceId,                                        // Johannes's workspace
      "since": formatter.string(from: start),                             // time span - from start to end of month
      "until": formatter.string(from: end)
    ]

    print("Parameters:")
    debugPrint(params)
    
    guard let bearerToken = getCredential() else {
      print("Bearer token could not be created")
      return
    }
    
    // 3. setup Authorization
    let headers: HTTPHeaders = [
      "Authorization": "Basic \(bearerToken)"
    ]
    
    // 4. fire request
    // closure is called async
    Alamofire.request("https://toggl.com/reports/api/v2/summary",
                      method: .get,
                      parameters: params,
                      encoding: URLEncoding.queryString,
                      headers: headers)
      .responseData { response in
        if !response.result.isSuccess {
          print("Request failed")
          return
        }
        // 5. parse ApiResponse from request
        do {
          let data = try JSONDecoder().decode(ApiResponse.self, from: response.result.value!)
          guard let millis = data.total_grand else {
            print("Total grand was not loaded")
            return
          }
          self.togglWorkedInMonth = millis / 1000 / 60 / 60
          self.renderTogglHours()
        } catch {
          print("Decoding failed")
          return
        }
      }
  }
  
  
  /**
   Returns the amount of workable hours in the current month.
   */
  func getHoursInMonth() -> Int {
    let calendar = NSCalendar.current
    let components = calendar.dateComponents([.year, .month], from: Date())
    guard let start = calendar.date(from: components) else { return 0 }
    let calRange = calendar.range(of: .day, in: .month, for: start)!
    let num = calRange.count

    print("\(num) days in this month")
    let allDays = Array(0..<num).map { calendar.date(byAdding: .day, value: $0, to: start) }

    let workdays = allDays.filter {
      if let d = $0 {
        return !calendar.isDateInWeekend(d)
      } else {
        return false
      }
    }
    print("\(workdays.count) workdays in this month")
    return workdays.count * hoursPerDay
  }
  
  /**
   Returns the value of the input box as an int, or nil
   if it wasn't possible (or the value was out of bounds)
   */
  func getInputText() -> Int? {
    guard let value = inputText.text else {
      return nil
    }
    guard let iValue = Int(value) else {
      print("Workload was not an int")
      return nil
    }
    
    print("Value is \(iValue)")
    
    if iValue <= 0 || iValue > 100 {
      print("Value was out of range (0..100]")
      return nil
    }
    return iValue
  }
  /**
   Recalculate the workload hours.
   If the input box has an invalid value, write "Nope" as
   the output.
   */
  func calculateAndRender() -> Void {
    guard let inputValue = getInputText() else {
      outputLabel.text = "Nope"
      return
    }
    neededHours = Int(floor((Double(inputValue) / 100.0) * Double(hoursInMonth)))
    outputLabel.text = "\(neededHours) hours"
    
    renderTogglHours()
  }
  
  func renderTogglHours() -> Void {
    var extra = ""
    if togglWorkedInMonth >= neededHours {
      extra = "You're golden."
    }
    else {
      let diff = neededHours - togglWorkedInMonth
      extra = "You need \(diff) more."
    }
    if neededHours == 0 {
      extra = ""
    }
    togglHoursLabel.text = "Toggl says you've worked for \(togglWorkedInMonth) hours. \(extra)"
  }

  //MARK: actions
  
  /** Calculate button click handler */
  @IBAction func calculateClick(_ sender: Any) {
    self.view.endEditing(true)
    calculateAndRender()
  }
  
  //MARK: UITextFieldDelegate
  
  /** Text field "Done" handler */
  func textFieldShouldReturn(_ textField: UITextField) -> Bool {
    inputText.resignFirstResponder()
    return true
  }
  
  /** Text field unfocus handler */
  func textFieldDidEndEditing(_ textField: UITextField) {
    calculateAndRender()
    
    guard let input = Int(inputText.text ?? "") else {
      return
    }
    
    UserDefaults.standard.set(input, forKey: ViewController.PERCENTAGE)
  }
  
  /** When the API token text field is changed, update the userDefaults */
  @IBAction func apiTokenValueChanged(_ sender: UITextField) {
    guard let text = apiTokenText.text else {
      return
    }
    print("Setting API key to \(text)")
    UserDefaults.standard.set(
      text,
      forKey: ViewController.TOGGL_API_TOKEN)
  }
  
  @IBAction func workspaceIDValueChanged(_ sender: UITextField) {
    guard let text = workspaceIdText.text else {
      return
    }
    print("Setting workspace ID to \(text)")
    guard let wsID = Int(text) else {
      print("WSID not int parseable")
      return
    }
    UserDefaults.standard.set(
      wsID,
      forKey: ViewController.TOGGL_ACTIVE_WORKSPACE_ID
    )
  }
}

